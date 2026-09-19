# Mobile player update (iOS cloud build 16)

Reference: Tencent Video mobile-app usage documentation, not the desktop player
and not the user's comparison screenshots.

Verified reference: https://shouyou.3dmgame.com/gl/386589.html (2022-04-11).
The article describes the mobile fullscreen button, bottom-right speed selection,
and temporary 3x playback on long press. This is historical documentation, not
verification of the latest Tencent app or a claim of identical functionality.

Implemented: landscape fullscreen, system UI hiding, 3-second control timeout,
tap to show/hide, double tap play/pause, horizontal seek preview committed on
release, temporary 3x long press with speed restoration, touch lock, bottom
episode selection, and existing next-episode playback. The video keeps its
aspect ratio, including any letterboxing, to avoid cropping subtitles.

Controls remain visible when paused and during a drag. Menus prevent the
auto-hide timer from hiding controls while a menu is open. Locking disables
seek/play gestures and hides normal controls; tap reveals the unlock button.
System back first unlocks instead of leaving the player.

No new Tencent branding, membership, download, casting, brightness or volume
gestures have been added. Current validation is Flutter analysis and widget
tests on Windows. iPhone landscape/rotation, safe-area layout and PiP still
require cloud Xcode compilation and device verification.

## Playback options

The bottom More menu now includes per-film intro/outro skipping and a sleep
timer. Intro/outro skipping is opt-in: the user sets durations in 5-second steps
(0-300 seconds each), stored separately per film and account. Source timestamps
are mapped through the existing HLS ad cuts. Short episodes with overlapping
intro/outro ranges are left intact. An intentional rewind after the initial
intro skip is allowed. This does not detect credits from video/audio content.

Sleep choices: finish this episode, finish two episodes including this one,
or stop after 15/30/60/90 minutes of wall-clock time (including pauses).
Manual switches do not consume an episode; automatic credits skipping does.
The sleep limit wins over automatic next-episode playback. At the last available
episode it stops even if two were requested. Limits are session-only and can
be cancelled or replaced. Stop pauses media and saves progress, not force-quits
the app. Native PiP is stopped as well; Android PiP boundaries use position
polling and may be up to a second late. Background and PiP timing still need
real-device verification.

Automatic HLS ad filtering remains enabled in the normal source preparation
path and does not depend on either new option.

Build 14 makes every fullscreen exit path wait for portrait before popping the
route, including the top back button, bottom fullscreen button and system back.
After an explicit exit, automatic landscape entry remains suppressed for that
detail page, while the manual fullscreen button continues to work. Orientation
restrictions are released when leaving the player page.

Build 16 recognizes explicit HLS ad cues and high-confidence numbered splices.
A splice is removed only when a short independent sequence is surrounded by
long consecutive main-video runs and playback resumes at exactly the next main
segment. Discontinuities, CDN changes, duration, or a sequence gap alone never
remove video.
