<script lang="ts">
  import type { VoiceCallView } from './generated/workspace';

  let { call, floating, mute, end }: {
    call: VoiceCallView;
    floating: boolean;
    mute: (microphone: boolean, muted: boolean) => void;
    end: () => void;
  } = $props();
</script>

<div class="voice-controls" class:voice-floating={floating} role="group" aria-label="Voice Call">
  <button type="button" disabled={call.phase === 'ending'}
    onclick={() => mute(true, !call.microphoneMuted)}>
    {call.microphoneMuted ? 'Unmute Microphone' : 'Mute Microphone'}
  </button>
  <button type="button" disabled={call.phase === 'ending'}
    onclick={() => mute(false, !call.speakerMuted)}>
    {call.speakerMuted ? 'Unmute Speaker' : 'Mute Speaker'}
  </button>
  <button type="button" onclick={end}>End Call</button>
</div>
