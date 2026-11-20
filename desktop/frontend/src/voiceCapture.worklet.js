class VoiceCapture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.frames = new Int16Array(2400);
    this.position = 0;
    this.phase = 0;
    this.total = 0;
    this.count = 0;
  }

  process(inputs) {
    const samples = inputs[0]?.[0];
    if (!samples) return true;
    for (const sample of samples) {
      this.total += sample;
      this.count += 1;
      this.phase += 24000;
      if (this.phase < sampleRate) continue;
      this.phase %= sampleRate;
      const value = Math.max(-1, Math.min(1, this.total / this.count));
      this.frames[this.position] = Math.round(value * (value < 0 ? 32768 : 32767));
      this.total = 0;
      this.count = 0;
      this.position += 1;
      if (this.position === this.frames.length) {
        this.port.postMessage(this.frames.buffer, [this.frames.buffer]);
        this.frames = new Int16Array(2400);
        this.position = 0;
      }
    }
    return true;
  }
}

registerProcessor('voice-capture', VoiceCapture);
