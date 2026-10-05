// AudioWorklet processors for the browser side of gateway voice.
//
// The rate is 48 kHz by construction: the AudioContext is created at 48000,
// and the Web Audio spec resamples a MediaStreamTrack whose rate differs, so
// nothing below resamples again. Opus stays in Rust (§80 principle 4) — these
// processors only move float samples.
//
// The capture side accumulates to exactly 960 samples (one 20 ms frame)
// *here*, not at the gateway. 960 is 7.5 render quanta of 128, so a gateway
// that accumulated would settle into 1024-sample batches and drift 6.7%
// against its own 20 ms clock; the AudioContext's render clock is the true
// 48 kHz one, and 960 samples on it is exactly 20 ms.

class PcmCapture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.frame = new Float32Array(960);
    this.filled = 0;
  }

  process(inputs) {
    const channel = inputs[0] && inputs[0][0];
    if (!channel) {
      return true; // no source yet; keep the node alive
    }

    let offset = 0;
    while (offset < channel.length) {
      const take = Math.min(960 - this.filled, channel.length - offset);
      this.frame.set(channel.subarray(offset, offset + take), this.filled);
      this.filled += take;
      offset += take;

      if (this.filled === 960) {
        // Transferred, not copied: the buffer is handed to the main thread
        // and a fresh one takes its place.
        const out = this.frame;
        this.port.postMessage(out, [out.buffer]);
        this.frame = new Float32Array(960);
        this.filled = 0;
      }
    }
    return true;
  }
}

class PcmPlayback extends AudioWorkletProcessor {
  constructor() {
    super();
    this.chunks = [];   // pending Float32Array(1920) stereo frames
    this.offset = 0;    // read position inside chunks[0], in floats
    this.played = 0;    // output frames written since construction
    this.peak = 0;      // loudest sample actually rendered, 0..1
    this.calls = 0;
    this.port.onmessage = (event) => {
      // A little buffering smooths network jitter; unbounded buffering would
      // grow the delay without bound, so old audio is dropped, not queued.
      this.chunks.push(event.data);
      while (this.chunks.length > 10) {
        this.chunks.shift();
        this.offset = 0;
      }
    };
  }

  // Everything here counts **frames**, never floats: an earlier version mixed
  // the two units, and the arithmetic converged towards the end of the quantum
  // without ever reaching it — an infinite loop that froze the audio render
  // thread and made every received frame silent. One unit, integer math.
  process(_inputs, outputs) {
    const out = outputs[0];
    if (!out || out.length === 0) {
      return true;
    }
    const left = out[0];
    const right = out.length > 1 ? out[1] : out[0];
    const wanted = left.length;

    let written = 0; // output frames written this call
    while (written < wanted) {
      const chunk = this.chunks[0];
      if (!chunk) {
        // Underrun: silence for the rest of the quantum, and the read offset
        // stays where it was so the next arrival resumes cleanly.
        for (let i = written; i < wanted; i++) {
          left[i] = 0;
          right[i] = 0;
        }
        break;
      }
      // The chunk is interleaved stereo: two floats per frame.
      const chunkFrames = (chunk.length - this.offset) / 2;
      const take = Math.min(chunkFrames, wanted - written);
      for (let f = 0; f < take; f++) {
        const l = chunk[this.offset + f * 2];
        const r = chunk[this.offset + f * 2 + 1];
        left[written + f] = l;
        right[written + f] = r;
        const loud = Math.max(Math.abs(l), Math.abs(r));
        if (loud > this.peak) this.peak = loud;
      }
      written += take;
      this.offset += take * 2;
      if (this.offset >= chunk.length) {
        this.chunks.shift();
        this.offset = 0;
      }
    }

    // Tell the main thread what playback actually did. This is how "frames
    // arrived" and "frames were rendered" stay distinguishable without ears —
    // the received-message counter cannot see a stalled processor.
    this.played += written;
    this.calls += 1;
    if (this.calls % 50 === 0) {
      // `peak` is the difference between "the pipeline works" and "the
      // pipeline works and carries silence": counters grow either way, and
      // zero-samples rendered into a speaker are still silence.
      this.port.postMessage({ played: this.played, peak: this.peak });
    }
    return true;
  }
}

registerProcessor('pcm-capture', PcmCapture);
registerProcessor('pcm-playback', PcmPlayback);
