---
layout: default
title: User Guide
description: EhViewer guide for browsing, downloads, offline reading, device sync, and backups
lang: en
permalink: /en/guide/
---
# User Guide

EhViewer is an E-Hentai and ExHentai gallery browser, downloader, and reader for iPhone, iPad, and Mac.

This guide follows the current app and covers browsing, downloads, the local library, reading, device sync, and backups.

*Some regions may require a proxy to access online content normally.*

## Browsing and Search

- Online gallery lists such as Home, Subscriptions, Popular, and Toplist support pull-to-refresh. On compact layouts, More opens Subscriptions, Popular, and Toplist.
- The search field accepts gallery keywords, gallery links, and tags. Search history and tag suggestions appear as you type; combine multiple tags or remove an active tag directly.
- Advanced Search filters by category, torrent availability, expunged galleries, minimum rating, and page-count range. It can also bypass the site's language, uploader, or tag filters.
- Open a gallery card for details. Select a tag to search for it, or use **Similar Galleries** to explore related results.
- Use **Settings → Filter Rules** to hide galleries by a title keyword, exact uploader, exact tag, or entire tag namespace. Each rule can be enabled, disabled, or removed independently.

## Quick Start

1. Open the app and search for a gallery on Browse.
2. Open a gallery, then select **Start Reading** to open the reader or **Add to Download** to save it locally.
3. Downloaded content appears in Local. Active and failed tasks can be managed in Downloads.
4. When an account session is needed, open **Settings → Account & Login** and use username and password, web login, or cookie login.

*Sign-in is only required for favorites, account-specific content, or ExHentai access. Public E-Hentai content is available in guest mode.*

## Downloads

After starting a download from a gallery detail page, the task appears on the Downloads page:

- Downloads support queuing, pausing, resuming, retrying, Start All, Pause All, and recovery of background tasks after relaunch.
- On compact layouts, select <img class="inline-app-icon" src="{{ '/assets/icons/ellipsis-circle.svg' | relative_url }}" alt="Download management" title="Download management"> to open Download Management for task controls, filters, sorting, and layout. Wide layouts expose these actions directly in the toolbar.
- The Downloads page supports list and card layouts. In list view, select <img class="inline-app-icon" src="{{ '/assets/icons/square-grid-2x2.svg' | relative_url }}" alt="Switch to card view" title="Switch to card view"> to switch to cards; in card view, select <img class="inline-app-icon" src="{{ '/assets/icons/list-bullet.svg' | relative_url }}" alt="Switch to list view" title="Switch to list view"> to return to the list.
- Search by title or tag, filter by All, Active, Paused, Completed, or Failed, and narrow the list further by gallery category.
- Sort by date added, title, progress, rating, or status; the Local library omits status sorting.
- Selection mode adds Select All and batch removal. Individual tasks support details, pause/resume, redownload, a custom label, and removal.

## Gallery Details

- The detail page shows the cover, title, author or uploader, category, page count, rating, language, file size, posting date, tags, comments, and page previews.
- **Start Reading** prefers downloaded pages and can open completed pages while a download is still running. **Add to Download** adds the gallery to the queue.
- Favorite, rate, share, or open similar galleries. The toolbar provides **Open on Site** and **Refresh**.
- When the site and account expose them, torrent and site-archive download options also appear.
- Preview thumbnails prefer local pages. Select any preview to start reading from that page.

## Local Library

- Local only shows galleries with readable media on this device and uses local covers and pages, so completed downloads remain available offline.
- Local supports title or tag search, category filtering, list/card layouts, and sorting by date added, title, progress, or rating.
- In selection mode, share selected galleries as a metadata-only `.ehgallery` package or a media-containing `.eharchive`, or remove them in a batch.
- History/Favorites uses a segmented control for Recently Read and Local Favorites. History entries show the last-read page.
- Use **Settings → Data & Backup** and choose **Update All** or **Update Missing Information Only** to refresh downloaded titles, authors, categories, page counts, upload dates, thumbnails, and ratings.

## Device Sync (Beta)

**Settings → Device Sync** directly merges the local libraries of two EhViewer devices on the same local network:

1. Open Device Sync on both devices and allow the system's local-network permission.
2. Select the other discovered device on one device. A six-digit verification code appears.
3. Enter that code on the other device. After the encrypted connection is established, confirm the device on both sides.
4. Review the gallery, page, and data totals to send and receive, then confirm the sync on both devices.
5. Keep both apps in the foreground and on the same local network until Sync Complete appears.

Sync compares both local libraries and transfers only missing downloaded-gallery metadata and media pages in both directions. It does not advertise or transfer accounts, passwords, or cookies. Fully committed galleries are retained after an interruption; reconnecting compares the libraries again and sends only what remains missing.

## Data Transfer Between Apple Devices

In **Settings → Data & Backup**:

1. On the original device, choose **Export Metadata (.ehgallery)** or **Export Archive (.eharchive)**.
2. Send the file with AirDrop, Files, or another sharing method.
3. On the new device, choose the matching import action and select the file from Files.

`.ehgallery` contains gallery metadata. It is compact and useful for migrating lists and details, but it does not include downloaded media.

`.eharchive` contains download records and media files for a complete local-library migration. You can also select only part of the Local library before exporting.

If both devices can run EhViewer at the same time, Device Sync is usually the quickest option. Use file export for durable backups, transfers across different networks, or importing later.

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
2. In EhViewer, open **Settings → Data & Backup → Import Archive (.eharchive)**.
3. Select the archive, wait for the import to finish, and check Local.

Existing downloads with the same name are not overwritten. If the archive is incomplete or contains unsupported files, the app reports the import result.

## Reader

- Tap the reader to show or hide controls. Use the progress slider and thumbnail strip to jump pages. **Reading Options** controls paged/continuous reading, page direction, and start position.
- On iPhone and iPad, you can also configure screen rotation, volume-button paging, and reversed volume-button direction.
- Reading progress is saved automatically. Use **Settings → Site & Browsing → Reset Reading Progress for Downloads** to reset all downloaded galleries.
- Long-press media or choose **Save Media** to save it to the system photo library. On Mac, media is saved to the Downloads folder.
- On Mac, use the arrow keys or trackpad gestures to turn pages.

## Settings and Account

- **Site & Browsing:** Switch between E-Hentai and ExHentai, control Japanese titles and tag translations, inspect or clear the cache, and reset downloaded reading progress. Clearing the cache keeps download tasks and media but removes local favorites and history.
- **Account & Login:** View guest/signed-in status, use username and password, web login, or cookie login, and clear the current cookie.
- **Filter Rules:** Manage title, uploader, tag, and tag-namespace blocking rules.
- **Data & Backup:** Maintain downloaded-gallery information and import or export `.ehgallery` and `.eharchive` files.
- **Device Sync:** Securely merge downloaded manga with a nearby device.
- **About:** Open this guide and view the current app version.

## Frequently Asked Questions

### The home page works, but gallery images fail to load. Why?

The site may be rate-limiting requests, the network may be unavailable, or the account session may be invalid. Check the network, refresh the page, and confirm that an ExHentai account has access if needed.

### Should I export metadata or an archive?

Use Device Sync when both devices are on the same local network and can open EhViewer; it fills missing content in both directions. Choose `.ehgallery` for gallery information and a smaller file. Choose `.eharchive` when downloaded images or videos should move too, or when you want a durable backup.

### Why is a gallery not visible after import?

Wait for the import or sync to finish, then open Local. `.ehgallery` contains no media, so it does not make a gallery appear in a local library that only shows readable downloads. For external archives, make sure the archive contains the supported directory structure.

### How do I clear the cache?

Open **Settings → Site & Browsing → Clear Cache**. This keeps downloaded files and tasks but removes local favorites and history; review the confirmation message before continuing.

### How do I report a problem?

Open a GitHub Issue with the OS version, app version, and reproducible steps. Do not include passwords, cookies, or other account credentials.

## Privacy

App data is stored locally. Network requests access the site selected by the user and download explicitly requested content. Nearby-device discovery runs only while Device Sync is open and does not advertise gallery, account, or cookie information.
