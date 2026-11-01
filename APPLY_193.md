# Bundle 193 - file send logs (LOGS ONLY) - 3.0.24+95

Why: the 13 MB video from the ZTE (app swiped away while sending, then a call)
shows the full length but plays under 1 second on BOTH phones. The old logs
can't show which copy was sent or if the send continued or started over.
Nothing about sending, receiving or playing changes. Only new log lines.

## New log lines

Copy step (Dart):
- `FILE_STAGED_OUTBOX file= size= source=<bytes> copy=<bytes> same=y|n`
- `FILE_STAGED_REUSED file= copy= source= same=y|n` (copy was already there; warning if sizes differ)
- `DIRECT_FILE_SEND_FROM_PROTECTED name= locked=<bytes> open_copy=<bytes>`

Send (native, tag LOCAL_LINK_TRANSPORT):
- `FILE_SEND_START transfer= file= size= sha=<8> chunks= done= reuse=y|n busy=y|n src=staged|view|locked|received|picker|other`
- `FILE_SEND_REPLACED ... old_size old_sha old_done old_src new_size new_sha new_src` (a 2nd send replaced the 1st)
- `FILE_SEND_RESTORED transfer= size= sha= done=N/T src=` (after reopen)
- `FILE_SEND_RESTORE_DROPPED transfer= reason=idle|bad_saved_info|too_many|source_missing|source_size_changed|source_content_changed`
- `FILE_SEND_SOURCE_BAD transfer= reason= size= now= src=` (file changed while sending)
- `FILE_SEND_DONE transfer= size= sha= chunks=`

Receive (native):
- `FILE_RECEIVE_START transfer= size= sha= chunks= resumed=y|n have=N`
- `FILE_RESUME_REQUEST transfer= have=N/T first_missing=K` (max 1 per 10 s)
- `FILE_CHUNK_IGNORED transfer= reason=different_file have_size have_sha got_size got_sha` (max 1 per 10 s)
- `FILE_RECEIVED_OK transfer= size= sha= chunks=`

Playing (Dart):
- `MEDIA_VIEW_SIZE key= bytes=`
- `VIDEO_PLAY_READY duration_ms= size= w= h=`
- `VIDEO_PLAY_STOP reason=end|paused|error pos_ms= duration_ms= size=`
- `VIDEO_PLAY_ERROR pos_ms= duration_ms= size= error=`

How to read: if `FILE_SEND_DONE` and `FILE_RECEIVED_OK` show the SAME size + sha,
both phones hold the same bytes, so the damage happened before sending.
`VIDEO_PLAY_STOP pos_ms≈1000` with a big `duration_ms` shows the early stop.

## Files
- NEW `android/app/src/main/kotlin/com/sajjad/locallink/FileSendLogPolicy.kt`
- NEW `android/app/src/test/kotlin/com/sajjad/locallink/File193Test.kt`
- NEW `test/video_play_log_193_test.dart`
- `LocalLinkTransportService.kt`, `file_transfer_service.dart`,
  `reliable_messaging_service.dart`, `media_view_cache.dart`,
  `chat_video_controller.dart`, `pubspec.yaml`, `local_link_app.dart`,
  `test/nearby_190_test.dart`

## Checks here
Kotlin compile clean (167 classes); Kotlin tests OK (335); flutter analyze
0 errors; nearby_190 + video_play_log_193 + the media/video tests passed.
Not tested on a phone yet.
