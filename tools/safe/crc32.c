/* crc32 — prints the CRC32 (IEEE) and size of a file or flash device. */
#include <stdio.h>
#include <stdint.h>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <file>\n", argv[0]); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 1; }
    uint32_t crc = 0xFFFFFFFFu;
    unsigned char buf[65536];
    size_t n, total = 0, i;
    int k;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) {
        for (i = 0; i < n; i++) {
            crc ^= buf[i];
            for (k = 0; k < 8; k++) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1)));
        }
        total += n;
    }
    fclose(f);
    printf("%08x %lu\n", crc ^ 0xFFFFFFFFu, (unsigned long)total);
    return 0;
}
