import { computeRms } from './pcm';

export type VadOptions = {
  silenceMs: number;
  energyThreshold: number;
};

export class EnergyVad {
  private hadSpeech = false;
  private lastSpeechAt = 0;
  private paused = false;

  constructor(private readonly options: VadOptions) {}

  pause(): void {
    this.paused = true;
  }

  resume(): void {
    this.paused = false;
    this.hadSpeech = false;
    this.lastSpeechAt = 0;
  }

  reset(): void {
    this.hadSpeech = false;
    this.lastSpeechAt = 0;
  }

  process(samples: Float32Array): boolean {
    if (this.paused) return false;

    const rms = computeRms(samples);
    const now = Date.now();

    if (rms >= this.options.energyThreshold) {
      this.hadSpeech = true;
      this.lastSpeechAt = now;
      return false;
    }

    if (
      this.hadSpeech &&
      now - this.lastSpeechAt >= this.options.silenceMs
    ) {
      this.hadSpeech = false;
      return true;
    }

    return false;
  }
}
