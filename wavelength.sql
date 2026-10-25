-- =====================================================
-- База данных проекта «Wavelength» (SQLite)
-- Социальная сеть для обсуждения музыки
-- =====================================================

PRAGMA foreign_keys = ON;

-- ---------- 1. ПОЛЬЗОВАТЕЛИ ----------
CREATE TABLE users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT    NOT NULL UNIQUE,              -- @dmitry_vibe
    display_name  TEXT    NOT NULL,                     -- Дмитрий Е.
    email         TEXT    NOT NULL UNIQUE,
    password_hash TEXT    NOT NULL,                     -- хэш, не пароль
    bio           TEXT    DEFAULT '',
    avatar_url    TEXT,
    banner_url    TEXT,
    created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
    CHECK (length(username) BETWEEN 3 AND 30),
    CHECK (email LIKE '%_@_%._%')
);

-- ---------- 2. ЖАНРЫ ----------
CREATE TABLE genres (
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
);

-- любимые жанры пользователя (экран онбординга)
CREATE TABLE user_genres (
    user_id  INTEGER NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    genre_id INTEGER NOT NULL REFERENCES genres(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, genre_id)
);

-- ---------- 3. ПОДКЛЮЧЕНИЕ МУЗЫКАЛЬНОГО СЕРВИСА ----------
CREATE TABLE music_connections (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    service      TEXT    NOT NULL DEFAULT 'yandex_music',
    external_id  TEXT,
    connected_at TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE (user_id, service)
);

-- ---------- 4. ТРЕКИ ----------
CREATE TABLE tracks (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    title        TEXT    NOT NULL,                      -- Грусть 2 (Соната)
    artist       TEXT    NOT NULL,                      -- OG BUDA, Mayot
    album        TEXT,                                  -- Kid A
    release_year INTEGER,
    cover_url    TEXT,
    duration_sec INTEGER CHECK (duration_sec > 0),
    genre_id     INTEGER REFERENCES genres(id) ON DELETE SET NULL
);

-- прослушивания (для «Чарты сегодня»)
CREATE TABLE track_plays (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    track_id  INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    user_id   INTEGER REFERENCES users(id) ON DELETE SET NULL,
    played_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ---------- 5. ПОСТЫ (ТРЕДЫ) ----------
CREATE TABLE posts (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    track_id   INTEGER REFERENCES tracks(id) ON DELETE SET NULL,
    body       TEXT    NOT NULL,
    rating     INTEGER CHECK (rating BETWEEN 1 AND 5),  -- оценка звёздами
    mood       TEXT    CHECK (mood IN ('energetic','melancholic','relaxing','nostalgic')),
    created_at TEXT    NOT NULL DEFAULT (datetime('now')),
    CHECK (length(body) BETWEEN 1 AND 1000)
);

-- ---------- 6. ОТВЕТЫ (вложенные) ----------
CREATE TABLE replies (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id          INTEGER NOT NULL REFERENCES posts(id)   ON DELETE CASCADE,
    user_id          INTEGER NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    parent_reply_id  INTEGER REFERENCES replies(id) ON DELETE CASCADE,  -- вложенность
    body             TEXT    NOT NULL,
    created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
    CHECK (length(body) BETWEEN 1 AND 1000)
);

-- ---------- 7. РЕАКЦИИ ----------
CREATE TABLE likes (
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id    INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, post_id)                      -- один лайк на пост
);

CREATE TABLE reposts (
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id    INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, post_id)
);

-- ---------- 8. ПОДПИСКИ ----------
CREATE TABLE follows (
    follower_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    following_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (follower_id, following_id),
    CHECK (follower_id <> following_id)                 -- нельзя подписаться на себя
);

-- ---------- 9. ХЭШТЕГИ (блок «Тренды сегодня») ----------
CREATE TABLE hashtags (
    id  INTEGER PRIMARY KEY AUTOINCREMENT,
    tag TEXT NOT NULL UNIQUE
);

CREATE TABLE post_hashtags (
    post_id    INTEGER NOT NULL REFERENCES posts(id)    ON DELETE CASCADE,
    hashtag_id INTEGER NOT NULL REFERENCES hashtags(id) ON DELETE CASCADE,
    PRIMARY KEY (post_id, hashtag_id)
);

-- ---------- 10. ПРОФИЛЬ: МУЗЫКАЛЬНАЯ СТЕНА И ПЛЕЙЛИСТЫ ----------
CREATE TABLE top_tracks (                               -- сетка 3×3 = 9 позиций
    user_id  INTEGER NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position BETWEEN 1 AND 9),
    PRIMARY KEY (user_id, position),
    UNIQUE (user_id, track_id)
);

CREATE TABLE playlists (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title      TEXT    NOT NULL,
    created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE playlist_tracks (
    playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    track_id    INTEGER NOT NULL REFERENCES tracks(id)    ON DELETE CASCADE,
    position    INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, track_id)
);

-- ---------- 11. УВЕДОМЛЕНИЯ ----------
CREATE TABLE notifications (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,   -- кому
    actor_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,   -- от кого
    type       TEXT    NOT NULL CHECK (type IN ('reply','mention','repost','like','follow')),
    post_id    INTEGER REFERENCES posts(id) ON DELETE CASCADE,
    text       TEXT,
    is_read    INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0,1)),
    created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ---------- ИНДЕКСЫ (ускоряют ленту, тред, уведомления) ----------
CREATE INDEX idx_posts_user_date   ON posts(user_id, created_at DESC);
CREATE INDEX idx_posts_date        ON posts(created_at DESC);
CREATE INDEX idx_replies_post      ON replies(post_id, created_at);
CREATE INDEX idx_likes_post        ON likes(post_id);
CREATE INDEX idx_follows_following ON follows(following_id);
CREATE INDEX idx_notif_user        ON notifications(user_id, is_read, created_at DESC);
CREATE INDEX idx_plays_track_date  ON track_plays(track_id, played_at);

-- =====================================================
-- ТЕСТОВЫЕ ДАННЫЕ
-- =====================================================

INSERT INTO genres(name) VALUES
 ('Рок'),('Хип-хоп'),('Электроника'),('Джаз'),('Поп'),
 ('R&B'),('Инди'),('Классика'),('Метал'),('Фолк');

-- password_hash здесь условный; в приложении хранится bcrypt-хэш
INSERT INTO users(username, display_name, email, password_hash, bio) VALUES
 ('dmitry_vibe',   'Дмитрий Е.', 'dmitry@example.com', 'hash1', 'Меломан со стажем. Ищу забытые жемчужины винила 70-х.'),
 ('alina_synth',   'Алина Радио','alina@example.com',  'hash2', 'Синтвейв и ночные прогулки.'),
 ('jazz_traveler', 'Павел Круг', 'pavel@example.com',  'hash3', 'Джаз и путешествия.'),
 ('sofia_listen',  'София Ли',   'sofia@example.com',  'hash4', ''),
 ('vinyldigger',   'Антон В.',   'anton@example.com',  'hash5', '');

INSERT INTO user_genres VALUES (1,1),(1,3),(1,7),(1,2),(2,3),(3,4),(4,7),(5,1);

INSERT INTO music_connections(user_id, service) VALUES (1,'yandex_music');

INSERT INTO tracks(title, artist, album, release_year, duration_sec, genre_id) VALUES
 ('Everything In Its Right Place','Radiohead','Kid A',2000,251,3),
 ('Грусть 2 (Соната)','OG BUDA, Mayot','Грусть 2',2022,184,2),
 ('PSP-FLOW','Слава КПСС, 163ONMYNECK','Единственный гость',2021,176,2),
 ('Genesis','Justice','Cross',2007,234,3),
 ('Starless','King Crimson','Red',1974,740,1),
 ('Nightcall','Kavinsky','OutRun',2013,258,3),
 ('Time','Pink Floyd','The Dark Side of the Moon',1973,413,1);

INSERT INTO posts(user_id, track_id, body, rating, mood, created_at) VALUES
 (1,2,'Переслушиваю OG BUDA сегодня вечером. Этот альбом до сих пор звучит так, будто его прислали из глубокого космоса будущего.',5,'melancholic','2026-10-25 20:46:00'),
 (2,3,'Уже слышали этот сумасшедший альбом? Просто мясо.',4,'energetic','2026-10-25 19:59:00'),
 (3,NULL,'Немного меланхоличного полуночного джаза от легендарного Билла Эванса.',5,'relaxing','2026-10-25 17:00:00');

INSERT INTO replies(post_id, user_id, parent_reply_id, body) VALUES
 (1,4,NULL,'Определенно один из лучших! Но лично для меня Airbag круче.'),
 (1,1,1,'Спорный момент, но Airbag тоже топ.'),
 (1,5,NULL,'Согласен насчет перехода.');

INSERT INTO likes(user_id, post_id) VALUES (2,1),(3,1),(4,1),(5,1),(1,2),(3,2);
INSERT INTO reposts(user_id, post_id) VALUES (3,1),(5,1);
INSERT INTO follows(follower_id, following_id) VALUES (1,4),(1,5),(2,1),(3,1),(4,1);

INSERT INTO hashtags(tag) VALUES ('Radiohead'),('EverythingInItsRightPlace'),('постпанк');
INSERT INTO post_hashtags VALUES (1,1),(1,2);

INSERT INTO top_tracks VALUES (1,1,1),(1,4,2),(1,5,3),(1,7,4);
INSERT INTO playlists(user_id, title) VALUES (1,'Ночной эмбиент');
INSERT INTO playlist_tracks VALUES (1,1,1),(1,4,2);

INSERT INTO track_plays(track_id, user_id) VALUES
 (4,1),(4,2),(4,3),(4,4),(5,1),(5,2),(5,3),(6,1),(6,2),(7,1);

INSERT INTO notifications(user_id, actor_id, type, post_id, text, is_read) VALUES
 (1,4,'reply',1,'Определенно один из лучших!',0),
 (1,5,'mention',1,'Согласен насчет перехода.',0),
 (1,3,'repost',1,NULL,1),
 (1,2,'follow',NULL,NULL,1);

-- =====================================================
-- ПРИМЕРЫ ЗАПРОСОВ ПОД ЭКРАНЫ ИНТЕРФЕЙСА
-- =====================================================

-- Главная лента: посты с треком и счётчиками
-- SELECT p.id, u.display_name, u.username, p.body, t.title, t.artist,
--   (SELECT COUNT(*) FROM likes   l WHERE l.post_id = p.id) AS likes,
--   (SELECT COUNT(*) FROM replies r WHERE r.post_id = p.id) AS replies,
--   (SELECT COUNT(*) FROM reposts s WHERE s.post_id = p.id) AS reposts
-- FROM posts p JOIN users u ON u.id = p.user_id
-- LEFT JOIN tracks t ON t.id = p.track_id
-- ORDER BY p.created_at DESC;

-- Чарты: топ треков по прослушиваниям
-- SELECT t.title, t.artist, COUNT(*) AS plays
-- FROM track_plays tp JOIN tracks t ON t.id = tp.track_id
-- GROUP BY t.id ORDER BY plays DESC LIMIT 4;

-- Тренды: самые частые хэштеги
-- SELECT h.tag, COUNT(*) AS cnt FROM post_hashtags ph
-- JOIN hashtags h ON h.id = ph.hashtag_id GROUP BY h.id ORDER BY cnt DESC;
