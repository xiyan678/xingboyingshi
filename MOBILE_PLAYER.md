# Mobile player update (iOS cloud build 11)

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
