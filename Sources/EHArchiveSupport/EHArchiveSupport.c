#include "EHArchiveSupport.h"

#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

// The SDK ships libarchive but does not expose its C headers. Keep this tiny
// adapter deliberately limited to the stable APIs we need.
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
extern struct archive *archive_write_new(void);
extern int archive_write_set_format_zip(struct archive *);
extern int archive_write_open_filename(struct archive *, const char *);
extern int archive_write_header(struct archive *, struct archive_entry *);
extern int64_t archive_write_data(struct archive *, const void *, size_t);
extern int archive_write_close(struct archive *);
extern int archive_write_free(struct archive *);
extern struct archive_entry *archive_entry_new(void);
extern void archive_entry_free(struct archive_entry *);
extern void archive_entry_set_pathname(struct archive_entry *, const char *);
extern void archive_entry_set_size(struct archive_entry *, int64_t);
extern void archive_entry_set_filetype(struct archive_entry *, unsigned int);
extern void archive_entry_set_perm(struct archive_entry *, mode_t);

struct eh_archive_reader {
    struct archive *archive;
};

struct eh_archive_writer {
    struct archive *archive;
    struct archive_entry *entry;
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

eh_archive_writer *eh_archive_writer_open(const char *path) {
    if (path == NULL) {
        return NULL;
    }

    struct archive *archive = archive_write_new();
    if (archive == NULL || archive_write_set_format_zip(archive) != 0 ||
        archive_write_open_filename(archive, path) != 0) {
        if (archive != NULL) {
            archive_write_free(archive);
        }
        return NULL;
    }

    eh_archive_writer *writer = (eh_archive_writer *)calloc(1, sizeof(eh_archive_writer));
    if (writer == NULL) {
        archive_write_close(archive);
        archive_write_free(archive);
        return NULL;
    }
    writer->archive = archive;
    return writer;
}

int eh_archive_writer_begin_file(
    eh_archive_writer *writer,
    const char *path,
    uint64_t size
) {
    if (writer == NULL || writer->archive == NULL || writer->entry != NULL || path == NULL || size > INT64_MAX) {
        return -1;
    }

    struct archive_entry *entry = archive_entry_new();
    if (entry == NULL) {
        return -1;
    }
    archive_entry_set_pathname(entry, path);
    archive_entry_set_size(entry, (int64_t)size);
    archive_entry_set_filetype(entry, S_IFREG);
    archive_entry_set_perm(entry, 0644);
    if (archive_write_header(writer->archive, entry) != 0) {
        archive_entry_free(entry);
        return -1;
    }
    writer->entry = entry;
    return 0;
}

int64_t eh_archive_writer_write(eh_archive_writer *writer, const void *buffer, size_t length) {
    if (writer == NULL || writer->archive == NULL || writer->entry == NULL ||
        (buffer == NULL && length > 0)) {
        return -1;
    }
    return archive_write_data(writer->archive, buffer, length);
}

int eh_archive_writer_end_file(eh_archive_writer *writer) {
    if (writer == NULL || writer->archive == NULL || writer->entry == NULL) {
        return -1;
    }
    archive_entry_free(writer->entry);
    writer->entry = NULL;
    // archive_write_header() and archive_write_close() finish entries as
    // needed. Avoid forcing a format-specific finish here; ZIP writers may
    // report a warning even though the entry is valid and can continue.
    return 0;
}

const char *eh_archive_writer_error(eh_archive_writer *writer) {
    if (writer == NULL || writer->archive == NULL) {
        return "archive writer is unavailable";
    }
    return archive_error_string(writer->archive);
}

void eh_archive_writer_close(eh_archive_writer *writer) {
    if (writer == NULL) {
        return;
    }
    if (writer->entry != NULL) {
        archive_entry_free(writer->entry);
        writer->entry = NULL;
    }
    if (writer->archive != NULL) {
        archive_write_close(writer->archive);
        archive_write_free(writer->archive);
    }
    free(writer);
}
