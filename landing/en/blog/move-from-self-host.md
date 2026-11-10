---
title: Moving from self-hosted church-staff-pwa to Martha, sit
date: 2026-11-10
description: The self-hosted church-staff-pwa is no longer updated. Move your team members, schedules, and services to Martha, sit in about ten minutes.
---

The self-hosted church-staff-pwa is no longer updated. Martha, sit is the same scheduling app, hosted for you: no Firebase or Cloudflare to look after, and there are phone apps. This guide is for the admin who set up your church’s site, and takes about ten minutes.

Moving only reads your old site’s data. Nothing there is changed or deleted, so everyone can keep using the old site until you’re done.

Use a computer. The move file is made and downloaded on your computer, so it’s easiest to upload it from the same one.

## What comes over

- Team members’ names, emails, permissions, services, and small groups
- Every schedule, occasions, and team member order
- Services, roles, and your usual occasions

Passwords, push notifications, LINE notifications, the daily devotional, and the calendar connection don’t come over. Team members who sign in to Martha, sit with the same email pick up their own data. Connect your calendar again after the move.

## 1. Make the move file

Sign in with the Google account that set up your site and [open Cloud Shell](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https%3A%2F%2Fgithub.com%2Fhansli112%2Fchurch-staff-pwa&cloudshell_git_branch=main&cloudshell_workspace=.&cloudshell_tutorial=docs%2Fmove-to-martha.md&show=terminal). A guide (in Traditional Chinese) opens on the right. Click the terminal icon at the top right of step 1’s command, then press Enter in the terminal below.

When it finishes, it says how many team members and schedules it found. Check the numbers.

- If it says it found several projects (找到好幾個同工助手的專案), add `--project PROJECT_ID` before `--out move.json` at the end of the command and run it again, with one of the project IDs it lists.
- If it says it can’t find a project (找不到同工助手的專案) or can’t read one (讀不到), you’re probably signed in with a different Google account. Switch to the one that set up your site and try again.

## 2. Download the move file

Run this in the terminal:

```sh
cloudshell download "$HOME/move.json"
```

Your browser downloads `move.json`. It has your team members’ names and emails, so don’t post it to a group or send it to anyone. Delete it once it’s uploaded.

## 3. Upload it to Martha, sit

1. <span data-from-app="hide">Open the [web app](/home) and </span>Sign in with Google or email. If you sign up with email, open the link in the verification email first.
2. On **Join your church**, choose **Create a church**, then tap **Move from old version** at the bottom.
3. Tap **Choose move file** and pick the `move.json` you downloaded.
4. Check the number of team members and schedules. Under **This is me**, pick yourself to take over your serving and permissions from the old site.
5. Tap **Create church and move**. Whoever uploads the file is the new church’s admin.

## 4. Have your team join

Team members who came over are listed as not signed in yet. Go to **Settings** → **Invites**, create an invite link, and send it to your team’s group.

- Team members who sign in with the same email as on the old site are asked whether to join your church. Tapping **Join** brings their schedules with them.
- Old passwords don’t work. Anyone who signed in with an email and password should sign up again with the same email, or sign in with Google.
- Team members who had no email on the old site are asked whether a name is theirs when they join with the invite link using the same name as on the schedule.
- For someone using a different email, the admin taps **Merge a pending record** on that person’s page.

## After the move

The move happens once. Changes made on the old site afterward won’t come over, so pick a day and tell your team to use Martha, sit from then on.

You can keep the old site as a backup, or delete it yourself in the Firebase and Cloudflare consoles.

To set up the rest, see [Getting started: create your church and invite your team](/en/blog/getting-started/) and [Arrange serving: several weeks at once, drag to swap](/en/blog/plan-weeks/).
