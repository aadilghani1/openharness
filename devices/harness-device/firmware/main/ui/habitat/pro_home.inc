/* The dock-only companion. Its entire middle is always the same control
 * surface; summaries and delivered letters never change what a tap means. */
static void pro_home_header(ht_scene_t *f)
{
    const uint16_t ink = color(0x365343);
    pro_control(f, 548, 24, 128, 64, "Menu", A_LAUNCHER, 0, true);
    const char *tab = "Workspace";
    for (int i = 0; i < s.tab_count; i++)
        if (!strcmp(s.tabs[i].id, s.selected_tab)) { tab = s.tabs[i].name; break; }
    ht_pro_text(f, 44, 36, 480, &ht_pro_32, ink,
        !s.connected ? "Connect to Harness" :
        s.loading ? "Finding your workspace..." : tab);
    pro_hit(32, 24, 496, 80, A_TABS, 0, s.connected && !s.loading);
}
static void pro_home_footer(ht_scene_t *f, agent_t *a, bool recap)
{
    const uint16_t ink = color(0x263b34);
    const uint16_t dim = color(0x627466);
    ht_pro_rect(f, 0, 596, 720, 124, 0, color(0xfbf9ef));
    ht_pro_text(f, 44, 604, 468, &ht_pro_32, ink, a ? a->name : "Choose a pane");
    const char *status = !s.connected ? "Connect to your computer" :
        s.loading ? "One moment..." : s.voice_retry_until ? "Voice was not sent. Try again." :
        s.nap ? "Taking a little rest" : a && is_question(a->id) ? "Needs your answer" :
        s.speech_error_until ? "Voice unavailable. Text is still here." :
        pro_speech_visible() ? (s.speech.playing ? "Speaking. Touch to interrupt." : "One moment...") :
        a && a->busy ? (a->tool[0] ? a->tool : "Working") :
        "";
    char carrying[128];
    snprintf(carrying, sizeof carrying, "%d line%s from %s", carry.rows, carry.rows == 1 ? "" : "s", carry.source);
    if (carry.active) status = carrying;
    else if (carry.error[0]) status = "Selected text expired";
    ht_pro_text(f, 44, 656, 478, &ht_pro_24, dim, status);
    pro_hit(32, 598, 492, 104, A_AGENTS, 0, s.connected && !s.loading);
    if (carry.active || carry.error[0])
        pro_control(f, 548, 622, 128, 64, "Drop", A_CARRY_DROP, 0, true);
    else if (visit.available)
        pro_control(f, 548, 622, 128, 64, "Return", A_RETURN, 0, s.connected && !visit.pending);
    else if (a && is_question(a->id))
        pro_control(f, 548, 622, 128, 64, "Answer", A_QUESTION, 0, s.connected);
    else if (recap)
        pro_control(f, 548, 622, 128, 64, "Read", A_READER, 0, true);
}
static void pro_render_home(ht_scene_t *f)
{
    agent_t *a = active();
    bool has_summary = a && !a->busy && a->recap_ready && a->preview[0] &&
        s.connected && !s.loading && !s.nap && !s.voice_retry_until && !carry.active && !carry.error[0];
    bool speech = pro_speech_visible();
    bool has_text = has_summary || speech || carry.active || carry.error[0];
    pro_visual_background(f, s.scene_choice, character.id);
    pro_home_header(f);
    ht_character_mood_t mood = character_mood();
    ht_character_t portrait = character;
    if (speech) {
        // LISTENING names the reusable open-mouth artwork, not the UI state or
        // microphone. Its mouth follows speaker PCM amplitude during playback.
        mood = s.speech.playing ? HT_CHARACTER_LISTENING : HT_CHARACTER_IDLE;
        portrait.motion.reaction.pose.level = s.speech.level;
        portrait.motion.reaction.pose.emotion = s.speech.emotion;
    }
    pro_visual_character(f, &portrait, mood, has_text,
        has_text ? 280 : 185, has_text ? 115 : 164,
        ms(), s.quiet, notice_unread() > 0);
    if (has_text) {
        char carried[192];
        snprintf(carried, sizeof carried, "%d line%s from %s", carry.rows, carry.rows == 1 ? "" : "s", carry.source);
        ht_pro_rect(f, 40, 295, 640, 281, 26, color(0xfbf9ef));
        const char *body = carry.active ? (carry.excerpt[0] ? carry.excerpt : carried) :
            carry.error[0] ? "Select the text again, or drop it to start fresh." :
            speech ? s.speech.caption : a->preview;
        ht_pro_wrap(f, 64, 315, 592, 5, 0, &ht_pro_32, color(0x263b34), body);
    }
    pro_home_footer(f, a, has_summary);
    // Registered after chrome: the same center is voice with or without text.
    pro_hit(40, 106, 640, 474, A_PET, 0, true);
}
static void pro_render_voice(ht_scene_t *f)
{
    bool recording = !s.voice_start_pending && !s.voice_waiting && audio_client_recording();
    bool can_review = recording && cable_client_supports(CABLE_FEATURE_DRAFT) &&
        !s.voice_search && (s.voice_return == HOME || s.voice_return == AGENT || s.voice_return == SELECTION);
    pro_visual_background(f, s.scene_choice, character.id);
    ht_pro_text(f, 44, 36, 632, &ht_pro_32, color(0x365343), s.voice_target);
    pro_visual_character(f, &character, recording ? HT_CHARACTER_LISTENING : HT_CHARACTER_WORKING,
                          false, 185, 132, ms(), s.quiet, false);
    const char *title = s.voice_start_pending ? "Getting ready..." :
        recording ? (s.voice_review_preview ? "Release to review." : "Listening...") :
        s.voice_search ? "Finding..." :
        s.voice_review || s.voice_return == DRAFT || s.voice_return == FORM || question_view(s.voice_return) ?
        "Preparing your words..." : "Sending...";
    ht_pro_rect(f, 28, 480, 664, 112, 24, color(0xfbf9ef));
    ht_pro_text(f, 44, 496, 632, &ht_pro_42, color(0x263b34), title);
    ht_pro_text(f, 44, 554, 632, &ht_pro_24, color(0x627466),
        recording ? (can_review ? "Tap to send. Hold to review first." : "Tap to finish speaking.") :
        "Your words stay with the selected pane.");
    ht_pro_rect(f, 0, 596, 720, 124, 0, color(0xfbf9ef));
    pro_control(f, 44, 618, 288, 72, s.voice_waiting ? "Stop sending" : "Discard", A_VOICE_ABORT, 0, true);
    if (can_review) pro_control(f, 388, 618, 288, 72, "Review first", A_VOICE_STOP, 1, true);
    else ht_pro_text(f, 388, 642, 288, &ht_pro_24, color(0x627466), recording ? "Tap the creature to finish" : "One moment...");
    pro_hit(40, 106, 640, 474, A_PET, 0, recording);
}
