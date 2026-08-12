#include "EHArchiveSupport.h"

#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

// The SDK ships libarchive but does not expose its C headers. Keep this tiny
// adapter deliberately limited to the stable read-only API we need.
struct archive;
struct archive_entry;

extern struct archive *archive_read_new(void);
extern int archive_read_support_filter_all(struct archive *);
extern int archive_read_support_format_all(struct archive *);
extern int archive_read_open_filename(struct archive *, const char *, size_t);
extern int archive_read_next_header(struct archive *, struct archive_entry **);
extern int64_t archive_read_data(struct archive *, void *, size_t);
extern int archive_read_data_skip(struct archive *);
extern int archive_read_free(struct archive *);
extern const char *archive_error_string(struct archive *);
extern const char *archive_entry_pathname(const struct archive_entry *);
extern int64_t archive_entry_size(const struct archive_entry *);
extern mode_t archive_entry_filetype(const struct archive_entry *);

struct eh_archive_reader {
    struct archive *archive;
};

eh_archive_reader *eh_archive_open(const char *path) {
    if (path == NULL) {
        return NULL;
    }

    struct archive *archive = archive_read_new();
    if (archive == NULL) {
        return NULL;
    }
    archive_read_support_filter_all(archive);
    archive_read_support_format_all(archive);
    if (archive_read_open_filename(archive, path, 10240) != 0) {
        archive_read_free(archive);
        return NULL;
    }

    eh_archive_reader *reader = (eh_archive_reader *)calloc(1, sizeof(eh_archive_reader));
    if (reader == NULL) {
        archive_read_free(archive);
        return NULL;
    }
    reader->archive = archive;
    return reader;
}

int eh_archive_next(
    eh_archive_reader *reader,
    const char **path,
    uint64_t *size,
    int *is_directory
) {
    if (reader == NULL || reader->archive == NULL || path == NULL || size == NULL || is_directory == NULL) {
        return -1;
    }

    struct archive_entry *entry = NULL;
    int result = archive_read_next_header(reader->archive, &entry);
    if (result != 0) {
        return result;
    }

    const char *entry_path = archive_entry_pathname(entry);
    int64_t entry_size = archive_entry_size(entry);
    *path = entry_path == NULL ? "" : entry_path;
    *size = entry_size < 0 ? 0 : (uint64_t)entry_size;
    *is_directory = archive_entry_filetype(entry) == S_IFDIR ||
        ((*path)[0] != '\0' && (*path)[strlen(*path) - 1] == '/');
    return 0;
}

int64_t eh_archive_read(eh_archive_reader *reader, void *buffer, size_t length) {
    if (reader == NULL || reader->archive == NULL || buffer == NULL) {
        return -1;
    }
    return archive_read_data(reader->archive, buffer, length);
}

int eh_archive_skip(eh_archive_reader *reader) {
    if (reader == NULL || reader->archive == NULL) {
        return -1;
    }
    return archive_read_data_skip(reader->archive);
}

const char *eh_archive_error(eh_archive_reader *reader) {
    if (reader == NULL || reader->archive == NULL) {
        return "archive reader is unavailable";
    }
    return archive_error_string(reader->archive);
}

void eh_archive_close(eh_archive_reader *reader) {
    if (reader == NULL) {
        return;
    }
    if (reader->archive != NULL) {
        archive_read_free(reader->archive);
    }
    free(reader);
}
