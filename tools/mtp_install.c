// Talks to a USB-connected Garmin watch over MTP:
//   mtp_install <file.prg>               copies the app into GARMIN/Apps, replacing any file of the same name
//   mtp_install --log-on <NAME>          creates GARMIN/Apps/LOGS/<NAME>.TXT so the app's System.println output is kept
//   mtp_install --log-read <NAME> <out>  copies GARMIN/Apps/LOGS/<NAME>.TXT to <out>
// Build: clang -o bin/mtp_install tools/mtp_install.c -I$(brew --prefix libmtp)/include -L$(brew --prefix libmtp)/lib -lmtp

#include <fcntl.h>
#include <libgen.h>
#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

// Id of the object named `name` directly inside `parent_id`, or 0
static uint32_t find_child(LIBMTP_mtpdevice_t *device, uint32_t storage_id, uint32_t parent_id, const char *name,
                           int folders_only) {
    uint32_t found = 0;
    LIBMTP_file_t *files = LIBMTP_Get_Files_And_Folders(device, storage_id, parent_id);
    for (LIBMTP_file_t *file = files; file != NULL;) {
        LIBMTP_file_t *next = file->next;
        int is_folder = file->filetype == LIBMTP_FILETYPE_FOLDER;
        if (!found && strcasecmp(file->filename, name) == 0 && (!folders_only || is_folder)) {
            found = file->item_id;
        }
        LIBMTP_destroy_file_t(file);
        file = next;
    }
    return found;
}

// Copies the local file at `path` (or an empty file when path is NULL) into `parent_id` as `remote_name`,
// replacing an existing file of that name
static int send_file(LIBMTP_mtpdevice_t *device, uint32_t storage_id, uint32_t parent_id, const char *path,
                     const char *remote_name) {
    uint32_t existing_id = find_child(device, storage_id, parent_id, remote_name, 0);
    if (existing_id != 0 && LIBMTP_Delete_Object(device, existing_id) != 0) {
        fprintf(stderr, "Could not remove the old %s\n", remote_name);
        LIBMTP_Dump_Errorstack(device);
        return 1;
    }
    struct stat info = {0};
    if (path != NULL && stat(path, &info) != 0) {
        perror(path);
        return 1;
    }
    int descriptor = open(path != NULL ? path : "/dev/null", O_RDONLY);
    LIBMTP_file_t *file = LIBMTP_new_file_t();
    file->filename = strdup(remote_name);
    file->filesize = info.st_size;
    file->filetype = LIBMTP_FILETYPE_UNKNOWN;
    file->parent_id = parent_id;
    file->storage_id = storage_id;
    int result = LIBMTP_Send_File_From_File_Descriptor(device, descriptor, file, NULL, NULL);
    close(descriptor);
    if (result != 0) {
        fprintf(stderr, "Copy of %s failed\n", remote_name);
        LIBMTP_Dump_Errorstack(device);
    }
    LIBMTP_destroy_file_t(file);
    return result != 0;
}

int main(int argc, char **argv) {
    int is_install = argc == 2;
    int is_log_on = argc == 3 && strcmp(argv[1], "--log-on") == 0;
    int is_log_read = argc == 4 && strcmp(argv[1], "--log-read") == 0;
    if (!is_install && !is_log_on && !is_log_read) {
        fprintf(stderr, "usage: mtp_install <file.prg> | --log-on <NAME> | --log-read <NAME> <out>\n");
        return 2;
    }

    LIBMTP_Init();
    LIBMTP_raw_device_t *raw_devices = NULL;
    int raw_device_count = 0;
    LIBMTP_mtpdevice_t *device = NULL;
    if (LIBMTP_Detect_Raw_Devices(&raw_devices, &raw_device_count) == LIBMTP_ERROR_NONE && raw_device_count > 0) {
        device = LIBMTP_Open_Raw_Device_Uncached(&raw_devices[0]);
    }
    free(raw_devices);
    if (device == NULL) {
        fprintf(stderr, "No watch found. Is it connected, with USB Mode set to MTP?\n");
        return 1;
    }
    LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED);
    uint32_t storage_id = device->storage->id;

    int result = 1;
    uint32_t garmin_id = find_child(device, storage_id, LIBMTP_FILES_AND_FOLDERS_ROOT, "GARMIN", 1);
    uint32_t apps_id = garmin_id ? find_child(device, storage_id, garmin_id, "Apps", 1) : 0;
    if (apps_id == 0) {
        fprintf(stderr, "GARMIN/Apps not found on the watch\n");
    } else if (is_install) {
        char *path_copy = strdup(argv[1]);
        result = send_file(device, storage_id, apps_id, argv[1], basename(path_copy));
        if (result == 0) {
            printf("Installed %s on %s. Unplug the watch to finish.\n", basename(path_copy), LIBMTP_Get_Modelname(device));
        }
        free(path_copy);
    } else {
        char log_name[256];
        snprintf(log_name, sizeof(log_name), "%s.TXT", argv[2]);
        uint32_t logs_id = find_child(device, storage_id, apps_id, "LOGS", 1);
        if (is_log_on) {
            if (logs_id == 0) {
                logs_id = LIBMTP_Create_Folder(device, "LOGS", apps_id, storage_id);
            }
            result = logs_id == 0 ? 1 : send_file(device, storage_id, logs_id, NULL, log_name);
            if (result == 0) {
                printf("Logging on: GARMIN/Apps/LOGS/%s\n", log_name);
            }
        } else {
            uint32_t log_id = logs_id ? find_child(device, storage_id, logs_id, log_name, 0) : 0;
            if (log_id == 0) {
                fprintf(stderr, "GARMIN/Apps/LOGS/%s not found\n", log_name);
            } else {
                result = LIBMTP_Get_File_To_File(device, log_id, argv[3], NULL, NULL);
                if (result == 0) {
                    printf("Saved GARMIN/Apps/LOGS/%s to %s\n", log_name, argv[3]);
                }
            }
        }
    }
    LIBMTP_Release_Device(device);
    return result != 0;
}
