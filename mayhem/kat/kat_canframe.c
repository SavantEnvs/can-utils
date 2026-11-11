/* Known-answer probe for lib.c: parse_canframe() / snprintf_canframe() / snprintf_long_canframe(). */
#include <stdio.h>
#include <string.h>

#include "lib.h"

struct kat {
	const char *in;
	int ret;		/* expected parse_canframe() result */
	const char *compact;	/* expected snprintf_canframe(sep=0), when ret != 0 */
	const char *longfmt;	/* expected snprintf_long_canframe(ASCII), or NULL */
};

static const struct kat kats[] = {
	{ "123#", CAN_MTU, "123#", NULL },
	{ "123#R", CAN_MTU, "123#R", "     123   [0]  remote request" },
	{ "123#R7", CAN_MTU, "123#R7", NULL },
	{ "7A1#r", CAN_MTU, "7A1#R", NULL },
	{ "123#00", CAN_MTU, "123#00", NULL },
	{ "12345678#", CAN_MTU, "12345678#", NULL },
	{ "123#1122334455667788", CAN_MTU, "123#1122334455667788", "     123   [8]  11 22 33 44 55 66 77 88   '.\"3DUfw.'" },
	{ "123#11.2233.44556677.88", CAN_MTU, "123#1122334455667788", NULL },
	{ "123#aabbcc", CAN_MTU, "123#AABBCC", NULL },
	{ "123#1122334455667788_E", CAN_MTU, "123#1122334455667788_E", NULL },
	{ "123#R8_9", CAN_MTU, "123#R8_9", NULL },
	{ "32345678#112233", CAN_MTU, "32345678#112233", NULL },
	{ "123##0112233", CANFD_MTU, "123##4112233", NULL },
	{ "123##1112233", CANFD_MTU, "123##5112233", NULL },
	{ "123##3", CANFD_MTU, "123##7", NULL },
	{ "45123#81:00:12345678#11223344.556677", CANXL_MTU, "45123#81:00:12345678#11223344556677", NULL },
	{ "1234", 0, NULL, NULL },
	{ "12#11", 0, NULL, NULL },
	{ "123#1", 0, NULL, NULL },
	{ "12G#11", 0, NULL, NULL },
	{ "123##", 0, NULL, NULL },
	{ "", 0, NULL, NULL },
};

int main(void)
{
	unsigned int i, run = 0, failed = 0;
	char buf[AFRSZ], in[128];
	union cfu cu;

	for (i = 0; i < sizeof(kats) / sizeof(kats[0]); i++) {
		const struct kat *k = &kats[i];
		int ret;

		strncpy(in, k->in, sizeof(in) - 1);
		in[sizeof(in) - 1] = 0;
		ret = parse_canframe(in, &cu);

		run++;
		if (ret != k->ret) {
			printf("FAIL parse '%s': got %d want %d\n", k->in, ret, k->ret);
			failed++;
			continue;
		}
		if (!ret)
			continue;

		run++;
		snprintf_canframe(buf, sizeof(buf), &cu, 0);
		if (strcmp(buf, k->compact)) {
			printf("FAIL compact '%s': got '%s' want '%s'\n", k->in, buf, k->compact);
			failed++;
		}

		if (k->longfmt) {
			run++;
			snprintf_long_canframe(buf, sizeof(buf), &cu, CANLIB_VIEW_INDENT_SFF | CANLIB_VIEW_ASCII);
			if (strcmp(buf, k->longfmt)) {
				printf("FAIL long '%s': got '%s' want '%s'\n", k->in, buf, k->longfmt);
				failed++;
			}
		}
	}

	printf("KAT: %u run; %u failed\n", run, failed);
	return failed != 0;
}
