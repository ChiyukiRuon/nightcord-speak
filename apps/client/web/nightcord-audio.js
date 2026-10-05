// Browser audio is a capability implementation, never a second TS client.
class NightcordAudio {
  constructor(onFrame) {
    this.onFrame = onFrame;
    this.generation = 0;
    this.muted = false;
    this.inputMuted = false;
    this.outputVolume = 1;
    this.level = 0;
    this.peak = 0;
    this.pending = null;
  }

  start(input, output) {
    // Coalesce the session event and an explicit audio-enable click.
    if (this.pending && input === this.input && output === this.output) {
      this.context?.resume().catch(() => {});
      return this.pending;
    }
    if (this.context && this.context.state !== 'closed' && this.stream?.getAudioTracks()[0]?.readyState === 'live' && input === this.input && output === this.output) {
      return this.context.resume();
    }
    this.stop();
    const generation = this.generation;
    this.input = input;
    this.output = output;
    // Construct and resume synchronously in the user's gesture, before permission awaits.
    const context = new AudioContext({ sampleRate: 48000 });
    this.context = context;
    const resume = context.resume();
    resume.catch(() => {});
    const request = this.open(context, generation, input, output);
    this.pending = request;
    request.finally(() => { if (this.pending === request) this.pending = null; }).catch(() => {});
    return request;
  }

  async open(context, generation, input, output) {
    let stream;
    try {
      if (!navigator.mediaDevices?.getUserMedia || !context.audioWorklet) {
        throw new Error('Audio requires HTTPS or localhost and AudioWorklet support');
      }
      const constraints = { echoCancellation: true, noiseSuppression: true, autoGainControl: false };
      this.fellBack = false;
      try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: { ...constraints,
          deviceId: input ? { exact: input } : undefined } });
      } catch (error) {
        if (generation !== this.generation) return;
        if (input && (error.name === 'OverconstrainedError' || error.name === 'NotFoundError')) {
          this.fellBack = true;
          stream = await navigator.mediaDevices.getUserMedia({ audio: constraints }).catch(() => null);
        } else if (error.name !== 'NotAllowedError' && error.name !== 'NotFoundError') {
          throw error;
        }
        // Listening still works when microphone permission is denied. The UI
        // keeps its enable-audio prompt so permission can be retried later.
      }
      if (generation !== this.generation) { stream?.getTracks().forEach(t => t.stop()); return; }
      this.stream = stream;
      stream?.getAudioTracks().forEach(t => { t.enabled = !this.inputMuted; });
      await context.audioWorklet.addModule(new URL('pcm-worklet.js', document.baseURI));
      if (generation !== this.generation) return;
      this.outputFellBack = false;
      if (output && context.setSinkId) {
        try { await context.setSinkId(output); }
        catch (_) { this.outputFellBack = true; }
      }
      if (generation !== this.generation) return;
      this.capture = new AudioWorkletNode(context, 'pcm-capture');
      this.playback = new AudioWorkletNode(context, 'pcm-playback', { outputChannelCount: [2] });
      this.gain = context.createGain();
      this.gain.gain.value = this.muted ? 0 : this.outputVolume;
      this.playback.connect(this.gain).connect(context.destination);
      this.capture.port.onmessage = event => {
        if (generation !== this.generation) return;
        const frame = event.data;
        let square = 0, peak = 0;
        const bytes = new Uint8Array(1 + frame.length * 4);
        const view = new DataView(bytes.buffer);
        bytes[0] = 1;
        for (let i = 0; i < frame.length; i++) {
          square += frame[i] * frame[i];
          peak = Math.max(peak, Math.abs(frame[i]));
          view.setFloat32(1 + i * 4, frame[i], true);
        }
        this.level = Math.sqrt(square / frame.length);
        this.peak = peak;
        this.onFrame(bytes);
      };
      if (stream) {
        this.source = context.createMediaStreamSource(stream);
        this.silent = context.createGain();
        this.silent.gain.value = 0;
        this.source.connect(this.capture).connect(this.silent).connect(context.destination);
      }
    } catch (error) {
      stream?.getTracks().forEach(t => t.stop());
      if (generation === this.generation) this.stop();
      throw error;
    }
  }

  stop() {
    this.generation++;
    this.pending = null;
    this.stream?.getTracks().forEach(t => t.stop());
    this.capture?.disconnect();
    this.playback?.disconnect();
    this.source?.disconnect();
    this.silent?.disconnect();
    this.gain?.disconnect();
    this.context?.close().catch(() => {});
    this.context = this.stream = this.capture = this.playback = this.gain = this.source = this.silent = null;
    this.level = this.peak = 0;
  }

  play(bytes) {
    if (!this.playback || this.muted || bytes[0] !== 2 || bytes.length < 9 || (bytes.length - 1) % 8 !== 0) return;
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const frame = new Float32Array((bytes.length - 1) / 4);
    for (let i = 0; i < frame.length; i++) {
      const value = view.getFloat32(1 + i * 4, true);
      if (!Number.isFinite(value)) return;
      frame[i] = value;
    }
    this.playback.port.postMessage(frame, [frame.buffer]);
  }

  mute(muted) { this.muted = muted; this.volume(this.outputVolume); }
  inputMute(muted) {
    this.inputMuted = muted;
    this.stream?.getAudioTracks().forEach(t => { t.enabled = !muted; });
  }
  volume(value) {
    this.outputVolume = Math.max(0, Math.min(2, value));
    if (this.gain) this.gain.gain.value = this.muted ? 0 : this.outputVolume;
  }
  test() {
    const context = this.context;
    if (!context || !this.gain) return;
    context.resume().catch(() => {});
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.frequency.value = 440;
    gain.gain.value = 0.1;
    oscillator.connect(gain).connect(this.gain);
    oscillator.start();
    oscillator.stop(context.currentTime + 0.3);
    oscillator.onended = () => { oscillator.disconnect(); gain.disconnect(); };
  }
  status() {
    const track = this.stream?.getAudioTracks()[0];
    const running = this.context?.state === 'running';
    return JSON.stringify({
      input: track ? { id: track.getSettings().deviceId || 'default', name: track.label || 'Microphone', available: track.readyState === 'live', fell_back: this.fellBack } : null,
      output: this.context ? { id: this.outputFellBack ? 'default' : this.output || 'default', name: 'Browser audio output', available: running, fell_back: this.outputFellBack } : null,
      healthy: running && track?.readyState === 'live', level: this.level, peak: this.peak,
      // The gateway alone owns VAD and its transmit gate.
      transmitting: false,
    });
  }
  async devices(direction) {
    if (direction === 'output' && !('setSinkId' in AudioContext.prototype)) return '[]';
    if (!navigator.mediaDevices?.enumerateDevices) return '[]';
    const devices = await navigator.mediaDevices.enumerateDevices();
    return JSON.stringify(devices.filter(d => d.kind === (direction === 'input' ? 'audioinput' : 'audiooutput') && d.deviceId)
      .map(d => ({ id: d.deviceId, name: d.label || d.deviceId, direction })));
  }
}
window.NightcordAudio = NightcordAudio;
