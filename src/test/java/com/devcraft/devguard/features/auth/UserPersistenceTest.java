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
