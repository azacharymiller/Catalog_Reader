# Team server (Supabase)

Shared notes, short-list, ratings, photos and sale results for the whole team. About 15 minutes to set up, free to start.

## 1. Create the project

1. Sign up at [supabase.com](https://supabase.com) with the farm's email and create a project (any name, region US East).
2. In the project, open **SQL Editor**, paste all of `schema.sql`, and press **Run**.

## 2. Turn on sign-in codes

The app signs people in with a 6-digit code sent by email, so nobody needs a password.

1. **Authentication → Sign In / Providers → Email**: leave Email on.
2. **Authentication → Email Templates → Magic Link**: replace the message body with:
   ```
   <p>Your Sale Catalog sign-in code is <strong>{{ .Token }}</strong></p>
   ```

## 3. Make the team

Each person signs in once from their iPad (Settings → Team server → Sign in). That creates their account. Then add them to the team in **SQL Editor**:

```sql
-- once
insert into teams (name) values ('Timbercreek') returning id;

-- for each person, using the team id from above
insert into team_members (team_id, user_id, display_name)
select '<team id>', id, 'Zach' from auth.users where email = 'zach@timbercreekfarm.com';
```

## 4. Connect the iPads

**Project Settings → API** shows the **Project URL** and the **anon public** key. Type both into the app's Settings → Team server, press Connect, then sign in. The anon key is safe on the iPads: row-level security lets each person reach only their own team's data.

## What syncs

| Item | Who can change it | Who sees it |
| --- | --- | --- |
| Short-list, bid ceiling | Anyone on the team | Team |
| Favorite, rating | Each person, their own | Team sees counts and the average |
| Ink notes and text | Each author, their own | Team |
| Photos and video | Each author, their own | Team |
| Results | Results reader; anyone types one in by hand | Everyone signed in |

The iPads sync every 15 seconds while connected and keep working offline.
