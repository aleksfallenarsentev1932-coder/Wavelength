using Microsoft.Data.Sqlite;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// ---------- База данных ----------
var dbPath  = Path.Combine(app.Environment.ContentRootPath, "wavelength.db");
var sqlPath = Path.Combine(app.Environment.ContentRootPath, "wavelength.sql");
var connStr = $"Data Source={dbPath};Foreign Keys=True";
const long CurrentUser = 1; // демо: «вошёл» пользователь №1 (@dmitry_vibe)

// При первом запуске создаём базу из SQL-скрипта
if (!File.Exists(dbPath))
{
    using var c = new SqliteConnection(connStr);
    c.Open();
    using var cmd = c.CreateCommand();
    cmd.CommandText = File.ReadAllText(sqlPath);
    cmd.ExecuteNonQuery();
}

// SELECT -> список строк
List<Dictionary<string, object?>> Query(string sql, params (string, object?)[] ps)
{
    using var c = new SqliteConnection(connStr);
    c.Open();
    using var cmd = c.CreateCommand();
    cmd.CommandText = sql;
    foreach (var (name, val) in ps) cmd.Parameters.AddWithValue(name, val ?? DBNull.Value);
    using var r = cmd.ExecuteReader();
    var list = new List<Dictionary<string, object?>>();
    while (r.Read())
    {
        var row = new Dictionary<string, object?>();
        for (int i = 0; i < r.FieldCount; i++)
            row[r.GetName(i)] = r.IsDBNull(i) ? null : r.GetValue(i);
        list.Add(row);
    }
    return list;
}

// INSERT / UPDATE / DELETE -> id последней вставки
long Exec(string sql, params (string, object?)[] ps)
{
    using var c = new SqliteConnection(connStr);
    c.Open();
    using var cmd = c.CreateCommand();
    cmd.CommandText = sql;
    foreach (var (name, val) in ps) cmd.Parameters.AddWithValue(name, val ?? DBNull.Value);
    cmd.ExecuteNonQuery();
    using var idCmd = c.CreateCommand();
    idCmd.CommandText = "SELECT last_insert_rowid()";
    return (long)(idCmd.ExecuteScalar() ?? 0L);
}

// Общий запрос поста: автор, трек, счётчики, лайкнул ли текущий пользователь
const string PostSql = @"
SELECT p.id, p.body, p.rating, p.mood, p.created_at,
       u.username, u.display_name,
       t.id AS track_id, t.title, t.artist, t.album,
       (SELECT COUNT(*) FROM likes   WHERE post_id = p.id) AS likes,
       (SELECT COUNT(*) FROM replies WHERE post_id = p.id) AS replies,
       (SELECT COUNT(*) FROM reposts WHERE post_id = p.id) AS reposts,
       EXISTS(SELECT 1 FROM likes WHERE post_id = p.id AND user_id = @me) AS liked
FROM posts p
JOIN users u ON u.id = p.user_id
LEFT JOIN tracks t ON t.id = p.track_id ";

var me = ("@me", (object?)CurrentUser);
var allowedMoods = new[] { "energetic", "melancholic", "relaxing", "nostalgic" };

// ---------- REST API ----------

// Лента
app.MapGet("/api/posts", () =>
    Results.Json(Query(PostSql + "ORDER BY p.created_at DESC, p.id DESC", me)));

// Тред: пост + ответы
app.MapGet("/api/posts/{id:long}", IResult (long id) =>
{
    var posts = Query(PostSql + "WHERE p.id = @id", me, ("@id", id));
    if (posts.Count == 0) return Results.NotFound(new { error = "Пост не найден" });
    var replies = Query(@"SELECT r.id, r.body, r.created_at, r.parent_reply_id,
                                 u.username, u.display_name
                          FROM replies r JOIN users u ON u.id = r.user_id
                          WHERE r.post_id = @id ORDER BY r.created_at, r.id", ("@id", id));
    return Results.Json(new { post = posts[0], replies });
});

// Создание поста (с проверкой данных)
app.MapPost("/api/posts", IResult (PostIn input) =>
{
    var body = input.Body?.Trim() ?? "";
    if (body.Length is 0 or > 1000)
        return Results.BadRequest(new { error = "Текст поста: от 1 до 1000 символов" });
    if (input.Rating is < 1 or > 5)
        return Results.BadRequest(new { error = "Оценка должна быть от 1 до 5" });
    if (input.Mood != null && !allowedMoods.Contains(input.Mood))
        return Results.BadRequest(new { error = "Недопустимое настроение" });
    if (input.TrackId != null &&
        Query("SELECT 1 FROM tracks WHERE id = @t", ("@t", input.TrackId)).Count == 0)
        return Results.BadRequest(new { error = "Трек не найден" });

    var id = Exec(@"INSERT INTO posts(user_id, track_id, body, rating, mood, created_at)
                    VALUES(@u, @t, @b, @r, @m, datetime('now','localtime'))",
        ("@u", CurrentUser), ("@t", input.TrackId), ("@b", body),
        ("@r", input.Rating), ("@m", input.Mood));
    return Results.Json(new { id }, statusCode: 201);
});

// Лайк (переключатель)
app.MapPost("/api/posts/{id:long}/like", IResult (long id) =>
{
    if (Query("SELECT 1 FROM posts WHERE id = @i", ("@i", id)).Count == 0)
        return Results.NotFound(new { error = "Пост не найден" });
    var has = Query("SELECT 1 FROM likes WHERE user_id = @u AND post_id = @p",
                    ("@u", CurrentUser), ("@p", id)).Count > 0;
    if (has) Exec("DELETE FROM likes WHERE user_id = @u AND post_id = @p", ("@u", CurrentUser), ("@p", id));
    else     Exec("INSERT INTO likes(user_id, post_id) VALUES(@u, @p)", ("@u", CurrentUser), ("@p", id));
    var n = Query("SELECT COUNT(*) AS n FROM likes WHERE post_id = @p", ("@p", id))[0]["n"];
    return Results.Json(new { liked = !has, likes = n });
});

// Ответ на пост
app.MapPost("/api/posts/{id:long}/replies", IResult (long id, ReplyIn input) =>
{
    var body = input.Body?.Trim() ?? "";
    if (body.Length is 0 or > 1000)
        return Results.BadRequest(new { error = "Ответ: от 1 до 1000 символов" });
    if (Query("SELECT 1 FROM posts WHERE id = @i", ("@i", id)).Count == 0)
        return Results.NotFound(new { error = "Пост не найден" });
    var rid = Exec(@"INSERT INTO replies(post_id, user_id, body, created_at)
                     VALUES(@p, @u, @b, datetime('now','localtime'))",
        ("@p", id), ("@u", CurrentUser), ("@b", body));
    return Results.Json(new { id = rid }, statusCode: 201);
});

// Список треков (для окна создания поста)
app.MapGet("/api/tracks", () =>
    Results.Json(Query("SELECT id, title, artist, album FROM tracks ORDER BY title")));

// Поиск по постам, трекам и исполнителям
app.MapGet("/api/search", (string? q) =>
{
    var like = "%" + (q ?? "").Trim() + "%";
    return Results.Json(Query(PostSql +
        "WHERE p.body LIKE @q OR t.title LIKE @q OR t.artist LIKE @q ORDER BY p.created_at DESC",
        me, ("@q", like)));
});

// Чарты
app.MapGet("/api/charts", () =>
    Results.Json(Query(@"SELECT t.title, t.artist, COUNT(*) AS plays
                         FROM track_plays tp JOIN tracks t ON t.id = tp.track_id
                         GROUP BY t.id ORDER BY plays DESC LIMIT 10")));

// Тренды (хэштеги)
app.MapGet("/api/trends", () =>
    Results.Json(Query(@"SELECT h.tag, COUNT(*) AS cnt
                         FROM post_hashtags ph JOIN hashtags h ON h.id = ph.hashtag_id
                         GROUP BY h.id ORDER BY cnt DESC LIMIT 5")));

// Профиль
app.MapGet("/api/users/{username}", IResult (string username) =>
{
    var users = Query(@"SELECT id, username, display_name, bio,
        (SELECT COUNT(*) FROM posts   WHERE user_id = users.id)      AS posts,
        (SELECT COUNT(*) FROM follows WHERE following_id = users.id) AS followers,
        (SELECT COUNT(*) FROM follows WHERE follower_id = users.id)  AS following
        FROM users WHERE username = @n", ("@n", username));
    if (users.Count == 0) return Results.NotFound(new { error = "Пользователь не найден" });
    var uid = users[0]["id"];
    return Results.Json(new
    {
        user = users[0],
        posts = Query(PostSql + "WHERE p.user_id = @uid ORDER BY p.created_at DESC", me, ("@uid", uid)),
        top = Query(@"SELECT tt.position, t.title, t.artist FROM top_tracks tt
                      JOIN tracks t ON t.id = tt.track_id WHERE tt.user_id = @uid ORDER BY tt.position", ("@uid", uid)),
        playlists = Query(@"SELECT p.title, COUNT(pt.track_id) AS n FROM playlists p
                            LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
                            WHERE p.user_id = @uid GROUP BY p.id", ("@uid", uid))
    });
});

// Уведомления
app.MapGet("/api/notifications", () =>
    Results.Json(Query(@"SELECT n.id, n.type, n.text, n.is_read, n.created_at, n.post_id,
                                u.display_name, u.username
                         FROM notifications n JOIN users u ON u.id = n.actor_id
                         WHERE n.user_id = @me ORDER BY n.created_at DESC, n.id DESC", me)));

// ---------- Сайт (wwwroot/index.html) ----------
app.UseDefaultFiles();
app.UseStaticFiles();

app.Run("http://localhost:5000");

// ---------- Модели входных данных ----------
record PostIn(string? Body, long? TrackId, int? Rating, string? Mood);
record ReplyIn(string? Body);
