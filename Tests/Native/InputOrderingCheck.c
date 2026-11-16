// Exercise the real input queue and sender. Only the encrypted network boundary
// is substituted: no connection, hardware input or crypto material is used.
#include "../../Engines/Client/TrunklineInputStream.c"

int AppVersionQuad[4] = {7, 1, 431, -1};
STREAM_CONFIGURATION StreamConfig;
CONNECTION_LISTENER_CALLBACKS ListenerCallbacks;
static unsigned failures, count;
static int target_x, target_y;
static const int expected[][3] = {
    {100, 200, BUTTON_ACTION_PRESS}, {140, 240, BUTTON_ACTION_RELEASE},
    {800, 700, BUTTON_ACTION_PRESS}, {800, 700, BUTTON_ACTION_RELEASE}
};
int sendInputPacketOnControlStream(unsigned char *data, int length, uint8_t channel, uint32_t flags, bool more) {
    PNV_INPUT_HEADER header = (PNV_INPUT_HEADER)data;
    uint32_t magic = LE32(header->magic);
    if (magic == MOUSE_MOVE_ABS_MAGIC) {
        PNV_ABS_MOUSE_MOVE_PACKET motion = (PNV_ABS_MOUSE_MOVE_PACKET)data;
        target_x = BE16(motion->x); target_y = BE16(motion->y);
        if (BE16(motion->width) != 999 || BE16(motion->height) != 999) ++failures;
    } else {
        int action = magic - 1;
        if (count >= 4 || target_x != expected[count][0] || target_y != expected[count][1] || action != expected[count][2]) {
            printf("FAIL button %u at %d,%d (action %d)\n", count, target_x, target_y, action);
            ++failures;
        }
        ++count;
    }
    return 0;
}
void flushInputOnControlStream(void) {}
bool isControlDataInTransit(void) { return false; }
// Legacy unencrypted input is not exercised by this fixture.
bool PltEncryptMessage(PPLT_CRYPTO_CONTEXT c, int a, int f, unsigned char *k, int kl, unsigned char *iv, int il, unsigned char *t, int tl, unsigned char *in, int len, unsigned char *out, int *ol) { abort(); }
int main(void) {
    LbqInitializeLinkedBlockingQueue(&packetQueue, MAX_QUEUED_INPUT_PACKETS);
    LbqInitializeLinkedBlockingQueue(&packetHolderFreeList, MAX_QUEUED_INPUT_PACKETS);
    PltCreateMutex(&batchedInputMutex);
    initialized = encryptedControlStream = true;
    // Hold delivery until both gestures have queued, like a busy sender thread.
    LiSendMousePositionEvent(100, 200, 1000, 1000);
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
    for (int i = 1; i <= 40; ++i) LiSendMousePositionEvent(100+i, 200+i, 1000, 1000);
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    LiSendMousePositionEvent(800, 700, 1000, 1000);
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    // Motion-only bursts still coalesce; button boundaries remain ordered.
    if (LbqGetItemCount(&packetQueue) != 7) { printf("FAIL queue lost gesture boundaries\n"); ++failures; }
    LbqSignalQueueDrain(&packetQueue);
    inputSendThreadProc(NULL);
    if (count != 4) ++failures;
    PLINKED_BLOCKING_QUEUE_ENTRY entry = LbqDestroyLinkedBlockingQueue(&packetHolderFreeList);
    while (entry) { void *data = entry->data; entry = entry->flink; free(data); }
    LbqDestroyLinkedBlockingQueue(&packetQueue);
    PltDeleteMutex(&batchedInputMutex);
    printf("%s: queued tap/drag/click targets and motion coalescing\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
