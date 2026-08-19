---
layout: default
title: User Guide
description: EhViewer user guide for iOS, iPadOS, and macOS
lang: en
permalink: /en/
---
# User Guide

EhViewer is a gallery browsing and reading app for E-Hentai and ExHentai on iPhone, iPad, and Mac.

This guide covers common features, downloads, reading, and data migration.

*Some regions may require a proxy to access online content normally.*

## Browsing and Search

- Home, Subscriptions, Popular, Toplist, and Favorites support pull-to-refresh.
- Use the search field to find galleries or tags. Tag suggestions appear as you type, and multiple tags can be combined.
- Advanced Search can filter results by category, rating, page count, and other conditions.
- Open a gallery card to view its details. Select a tag to jump directly to its search results.

## Quick Start

1. Open the app, choose a site on the Home page, or search for a gallery.
2. Open a gallery to view its details, then select the cover or reading action to open the reader.
3. If an account session is required, go to **Settings → Login** and choose username and password, web login, or cookie login.
4. Use **Settings → Browse** to configure title display, tag translations, and gallery-detail caching.

*You only need to sign in for account sessions, favorites, or ExHentai content.*

## Downloads

After starting a download from a gallery detail page, the task appears on the Downloads page:

- Downloads support queuing, pausing, resuming, retrying failed tasks, and restoring background work after relaunch.
- Select the <img class="inline-app-icon" src="{{ '/assets/icons/ellipsis-circle.svg' | relative_url }}" alt="Download management" title="Download management"> icon to open the menu, then choose **Sort** by date added, title, progress, or status.
- The Downloads page supports list and card layouts. In list view, select <img class="inline-app-icon" src="{{ '/assets/icons/square-grid-2x2.svg' | relative_url }}" alt="Switch to card view" title="Switch to card view"> to switch to cards; in card view, select <img class="inline-app-icon" src="{{ '/assets/icons/list-bullet.svg' | relative_url }}" alt="Switch to list view" title="Switch to list view"> to return to the list.
- Search download titles or tags, and filter tasks by All, Active, Paused, Completed, or Failed.
- Selection mode supports batch deletion. Individual tasks support viewing details, pausing/resuming, retrying, labeling, and deletion.

## Gallery Details

- The detail page shows the cover, title, uploader, category, page count, rating, and tags.
- Select **Read** to open the reader, or **Add to Download** to add the gallery to the download queue.
- You can favorite, rate, share, or open similar galleries.
- Preview thumbnails prefer downloaded pages when available. Select a tag to search for other galleries with the same tag.

## Data Transfer Between Apple Devices

In **Settings → Data Migration/Backup**:

1. On the original device, choose **Export Metadata (.ehgallery)** or **Export Archive (.eharchive)**.
2. Send the file with AirDrop, Files, or another sharing method.
3. On the new device, choose the matching import action and select the file from Files.

`.ehgallery` contains gallery metadata and is suitable for synchronizing lists and details.

`.eharchive` also contains downloaded media and is suitable for a complete download migration.

## Migrating from Android

Locate the Android download directory and package it with this structure:

```text
download.zip
└─download
   ├─xxx
   ├─xxx
   ├─xxx
   └─xxx
```

1. Transfer the archive to iPhone, iPad, or Mac using Files, AirDrop, or a cloud drive.
2. In EhViewer, open **Settings → Data Migration/Backup → Import Archive (.eharchive)**.
3. Select the archive, wait for the import to finish, and check the Downloads page.

Existing downloads with the same name are not overwritten. If the archive is incomplete or contains unsupported files, the app reports the import result.

## Reader

- Tap the reader to show or hide controls. **Reading Options** lets you choose paged or continuous reading, page-turn direction, and the start position.
- On iPhone and iPad, you can also configure screen rotation, volume-button paging, and reversed volume-button direction.
- Reading progress is saved automatically, so you can continue from the previous position.
- Long-press media or choose **Save Media** to save it to the system photo library. On Mac, media is saved to the Downloads folder.
- On Mac, use the arrow keys or trackpad gestures to turn pages.

## Settings and Account

- Use **Settings → Site** to switch between E-Hentai and ExHentai. ExHentai requires a valid account session.
- **Settings → Login** supports username and password, web login, and cookie login. You can also clear the current cookie.
- **Settings → Browse** controls Japanese titles, tag translations, and detail caching. Clearing the detail cache does not delete downloaded files.
- **Settings → About** shows the current app build version.

## Frequently Asked Questions

### The home page works, but gallery images fail to load. Why?

The site may be rate-limiting requests, the network may be unavailable, or the account session may be invalid. Check the network, refresh the page, and confirm that an ExHentai account has access if needed.

### Should I export metadata or an archive?

Choose `.ehgallery` when you only need gallery lists and reading information. Choose `.eharchive` when downloaded images or videos should be transferred as well.

### Why is a gallery not visible after import?

Wait for the import to finish, then open Downloads. Metadata import does not download missing media. For external archives, make sure the archive contains the supported directory structure.

### How do I clear the cache?

In **Settings → Browse**, disable detail caching or select **Clear Detail Cache**. This does not delete downloaded images, videos, or archives.

### How do I report a problem?

Open a GitHub Issue with the OS version, app version, and reproducible steps. Do not include passwords, cookies, or other account credentials.

## Privacy

App data is stored locally. Network requests are used only to access the sites selected by the user and to download content explicitly requested by the user.
