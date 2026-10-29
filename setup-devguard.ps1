[CmdletBinding()]
param([string]$ProjectPath = 'D:\DevGuard\DevGuard')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoUrl = 'https://github.com/dorinpatinvoh/DevGuard.git'
$commitMessage = 'feat: infrastructure setup with postgreSQL in docker configuration and user entity'
function Invoke-Checked {
    param([string]$Command, [string[]]$CommandArgs)
    & $Command @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw "$Command failed (exit $LASTEXITCODE)." }
}
foreach ($tool in @('git', 'docker')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool introuvable. Installez Git et Docker Desktop, puis relancez." }
}
New-Item -ItemType Directory -Force -Path $ProjectPath | Out-Null
Push-Location $ProjectPath
try {
    if (-not (Test-Path '.git')) {
        $entries = @(Get-ChildItem -Force)
        if ($entries.Count -gt 0) { throw 'Dossier non vide sans depot Git. Clonez le depot dans un dossier vide ou utilisez votre clone existant.' }
        Invoke-Checked git @('clone', '--branch', 'main', $repoUrl, '.')
    }
    $remote = & git remote get-url origin
    if ($LASTEXITCODE -ne 0 -or $remote -notmatch '^(https://github\.com/|git@github\.com:)dorinpatinvoh/DevGuard(\.git)?/?$') { throw 'origin ne correspond pas a dorinpatinvoh/DevGuard.' }
    $branch = & git branch --show-current
    if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Placez le depot sur main avant de relancer.' }
    Invoke-Checked git @('fetch', 'origin', 'main')
    Invoke-Checked git @('merge', '--ff-only', 'origin/main')
    foreach ($key in @('user.name', 'user.email')) {
        $value = & git config --get $key
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($value)) { throw "Configurez git config $key avant de relancer." }
    }
    $dockerReady = $false
    try { & docker info *> $null; $dockerReady = ($LASTEXITCODE -eq 0) } catch { $dockerReady = $false }
    if (-not $dockerReady) {
        $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if (Test-Path $desktop) { Start-Process $desktop | Out-Null }
        $deadline = (Get-Date).AddSeconds(120)
        do {
            Start-Sleep -Seconds 3
            try { & docker info *> $null; $ready = ($LASTEXITCODE -eq 0) } catch { $ready = $false }
        } until ($ready -or (Get-Date) -gt $deadline)
        if (-not $ready) { throw 'Docker Desktop ne repond pas. Activez les conteneurs Linux puis relancez.' }
    }
    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        function Invoke-Compose { Invoke-Checked docker-compose $args }
    } else {
        Invoke-Checked docker @('compose', 'version')
        function Invoke-Compose { Invoke-Checked docker (@('compose') + $args) }
    }
    $files = [ordered]@{}
    $files['.github/workflows/build.yml'] = @'
name: Java 21 and PostgreSQL 16
on: [push, pull_request]
permissions:
  contents: read
jobs:
  verify:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_DB: devguard_db
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: SecretPassword2026
        ports: [5432:5432]
        options: >-
          --health-cmd "pg_isready -U postgres -d devguard_db"
          --health-interval 5s --health-timeout 5s --health-retries 24
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: maven
      - name: Validate PowerShell syntax
        shell: pwsh
        run: |
          $tokens = $null
          $parseErrors = $null
          [System.Management.Automation.Language.Parser]::ParseFile("$PWD/setup-devguard.ps1", [ref]$tokens, [ref]$parseErrors) | Out-Null
          if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
      - run: mvn --batch-mode --no-transfer-progress verify
'@
    $files['.gitignore'] = @'
target/
.idea/
.vscode/
*.iml
*.log
.env
.env.*
!.env.example
'@
    $files['README.md'] = @'
# DevGuard

Spring Boot 3.3.13, Java 21, PostgreSQL 16, JPA et Lombok.

## Installation Windows

Prerequis : Git, Docker Desktop demarre (conteneurs Linux), Java 21 pour lancer le JAR et authentification GitHub configuree.

```powershell
Set-Location 'D:\DevGuard\DevGuard'
git pull --ff-only origin main
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-devguard.ps1
java -jar .\target\devguard-0.0.1-SNAPSHOT.jar
```

Le script embarque les sources, attend PostgreSQL, execute les tests avec Maven/Java 21 dans Docker, puis ajoute, commit et pousse sur main. Il ne supprime aucun volume et refuse de changer de depot ou de branche silencieusement. Si les fichiers sont deja a jour, aucun commit vide n'est cree.

Sante : http://localhost:8080/actuator/health

Les identifiants fournis sont ceux du developpement local. Les mots de passe des utilisateurs doivent etre haches par le futur service d'authentification avant stockage. Aucune API d'authentification n'est encore implementee.

Pour arreter PostgreSQL sans effacer les donnees : `docker compose stop`.
'@
    $files['docker-compose.yml'] = @'
services:
  postgres:
    image: postgres:16
    container_name: devguard-postgres
    restart: unless-stopped
    ports:
      - "127.0.0.1:5432:5432"
    environment:
      POSTGRES_DB: devguard_db
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: SecretPassword2026
    volumes:
      - devguard_postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d devguard_db"]
      interval: 5s
      timeout: 5s
      retries: 24
volumes:
  devguard_postgres_data:
'@
    $files['pom.xml'] = @'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>3.3.13</version><relativePath/></parent>
  <groupId>com.devcraft</groupId><artifactId>devguard</artifactId><version>0.0.1-SNAPSHOT</version><name>DevGuard</name>
  <properties><java.version>21</java.version></properties>
  <dependencies>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
    <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
    <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><optional>true</optional></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
  </dependencies>
  <build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId><configuration><excludes><exclude><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></exclude></excludes></configuration></plugin></plugins></build>
</project>
'@
    $files['src/main/java/com/devcraft/devguard/DevGuardApplication.java'] = @'
package com.devcraft.devguard;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DevGuardApplication {
    public static void main(String[] args) {
        SpringApplication.run(DevGuardApplication.class, args);
    }
}
'@
    $files['src/main/java/com/devcraft/devguard/features/auth/Role.java'] = @'
package com.devcraft.devguard.features.auth;

public enum Role {
    ADMIN, CLIENT, PARTENAIRE
}
'@
    $files['src/main/java/com/devcraft/devguard/features/auth/User.java'] = @'
package com.devcraft.devguard.features.auth;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "users")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class User {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, unique = true)
    private String email;

    @JsonIgnore
    @Column(nullable = false)
    private String password;

    private String nom;
    private String prenom;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Role role;

    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    @Column(nullable = false)
    private Instant updatedAt;
}
'@
    $files['src/main/resources/application.properties'] = @'
spring.application.name=devguard
server.port=8080
spring.datasource.url=${DB_URL:jdbc:postgresql://localhost:5432/devguard_db}
spring.datasource.username=${DB_USERNAME:postgres}
spring.datasource.password=${DB_PASSWORD:SecretPassword2026}
spring.datasource.driver-class-name=org.postgresql.Driver
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
spring.jpa.open-in-view=false
management.endpoints.web.exposure.include=health
management.endpoint.health.show-details=never
'@
    $files['src/test/java/com/devcraft/devguard/features/auth/UserPersistenceTest.java'] = @'
package com.devcraft.devguard.features.auth;

import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import static org.assertj.core.api.Assertions.*;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class UserPersistenceTest {
    @Autowired EntityManager entityManager;

    @Test
    void persistsUuidRoleAndTimestampsAndUpdatesTimestamp() {
        var user = User.builder().email("client@example.test").password("already-hashed")
                .nom("Test").prenom("Client").role(Role.CLIENT).build();
        entityManager.persist(user);
        entityManager.flush();
        var id = user.getId();
        var initialUpdate = user.getUpdatedAt();
        assertThat(id).isNotNull();
        assertThat(user.getCreatedAt()).isNotNull();
        assertThat(initialUpdate).isNotNull();
        entityManager.clear();
        var stored = entityManager.find(User.class, id);
        assertThat(stored.getRole()).isEqualTo(Role.CLIENT);
        stored.setNom("Modified");
        entityManager.flush();
        assertThat(stored.getUpdatedAt()).isAfterOrEqualTo(initialUpdate);
    }

    @Test
    void rejectsDuplicateEmails() {
        entityManager.persist(User.builder().email("duplicate@example.test").password("hash").role(Role.ADMIN).build());
        entityManager.flush();
        assertThatThrownBy(() -> {
            entityManager.persist(User.builder().email("duplicate@example.test").password("hash").role(Role.PARTENAIRE).build());
            entityManager.flush();
        }).isInstanceOf(RuntimeException.class);
    }

    @Test
    void rejectsMissingPassword() {
        assertThatThrownBy(() -> {
            entityManager.persist(User.builder().email("missing@example.test").role(Role.CLIENT).build());
            entityManager.flush();
        }).isInstanceOf(RuntimeException.class);
    }
}
'@

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $backupRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('DevGuard-backup-' + [guid]::NewGuid().ToString('N'))
    foreach ($relative in $files.Keys) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $ProjectPath $relative)) | Out-Null
    }
    foreach ($relative in $files.Keys) {
        $destination = Join-Path $ProjectPath $relative
        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        if (Test-Path $destination) {
            $backup = Join-Path $backupRoot $relative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
            Copy-Item -LiteralPath $destination -Destination $backup
        }
        [System.IO.File]::WriteAllText($destination, ($files[$relative] -replace "`r`n", "`n") + "`n", $encoding)
    }
    Invoke-Compose up -d
    $deadline = (Get-Date).AddSeconds(120)
    do {
        $health = & docker inspect --format '{{.State.Health.Status}}' devguard-postgres
        if ($LASTEXITCODE -ne 0) { throw 'Conteneur PostgreSQL introuvable.' }
        if ($health -eq 'unhealthy') { throw 'PostgreSQL unhealthy. Consultez docker logs devguard-postgres.' }
        if ($health -ne 'healthy') { Start-Sleep -Seconds 2 }
    } until ($health -eq 'healthy' -or (Get-Date) -gt $deadline)
    if ($health -ne 'healthy') { throw 'Delai de demarrage PostgreSQL depasse.' }
    # Maven et Java 21 fournis par Docker ; aucun Maven local requis.
    $mount = "type=bind,source=$((Get-Location).Path),target=/workspace"
    Invoke-Checked docker @('run', '--rm', '--network', 'container:devguard-postgres', '--mount', $mount,
        '--mount', 'type=volume,source=devguard_maven_cache,target=/root/.m2', '-w', '/workspace',
        'maven:3.9.9-eclipse-temurin-21', 'mvn', '--batch-mode', '--no-transfer-progress', 'verify')
    Invoke-Checked git @('add', '.')
    & git diff --cached --quiet
    $diffExit = $LASTEXITCODE
    if ($diffExit -eq 1) { Invoke-Checked git @('commit', '-m', $commitMessage) }
    elseif ($diffExit -ne 0) { throw 'Impossible de verifier les modifications Git.' }
    Invoke-Checked git @('push', 'origin', 'main')
    Write-Host 'DevGuard configure, tests passes et main synchronisee.' -ForegroundColor Green
    Write-Host "Sauvegarde des fichiers remplaces : $backupRoot"
    Write-Host 'Lancement (Java 21) : java -jar .\target\devguard-0.0.1-SNAPSHOT.jar'
} finally {
    Pop-Location
}
