/// A queue's one-shot time window is inclusive at start, exclusive at end.
bool queueWindowOpen(DateTime now, DateTime? start, DateTime? end) =>
    (start == null || !now.isBefore(start)) &&
    (end == null || now.isBefore(end));

int queueAvailableSlots(int limit, int running) =>
    (limit < 1 ? 1 : limit) > running ? (limit < 1 ? 1 : limit) - running : 0;
