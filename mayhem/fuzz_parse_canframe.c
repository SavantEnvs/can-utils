/* libFuzzer harness: ASCII CAN frame parser plus the two formatters that consume its output. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lib.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char buf[AFRSZ];
	union cfu cu;
	char *cs = malloc(size + 1);

	if (!cs)
		return -1;
	memcpy(cs, data, size);
	cs[size] = 0;

	/* 0 == string rejected (lib.h) */
	if (!parse_canframe(cs, &cu)) {
		free(cs);
		return -1;
	}
	free(cs);

	snprintf_canframe(buf, sizeof(buf), &cu, 0);
	snprintf_canframe(buf, sizeof(buf), &cu, 1);
	snprintf_long_canframe(buf, sizeof(buf), &cu, CANLIB_VIEW_INDENT_SFF);
	snprintf_long_canframe(buf, sizeof(buf), &cu,
			       CANLIB_VIEW_ASCII | CANLIB_VIEW_ERROR | CANLIB_VIEW_LEN8_DLC);
	snprintf_long_canframe(buf, sizeof(buf), &cu, CANLIB_VIEW_BINARY | CANLIB_VIEW_SWAP);

	return 0;
}
