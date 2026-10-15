const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

for (const file of ['apps/client/web/pcm-worklet.js', 'crates/ts-gateway/web/pcm-worklet.js']) {
  test(`${file}: 限幅保持声道比例、波形与静音`, () => {
    const processors = new Map();
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../..', file), 'utf8'), {
      AudioWorkletProcessor: class { constructor() { this.port = {}; } },
      sampleRate: 48000,
      registerProcessor: (name, cls) => processors.set(name, cls),
    });
    const limiter = new (processors.get('pcm-limiter'))();
    let shaped = 0;
    for (let block = 0; block < 40; block++) {
      const left = Float32Array.from({ length: 128 }, (_, i) => Math.sin((block * 128 + i) * 0.1) * 4);
      const right = Float32Array.from(left, s => s * 0.25);
      const output = [new Float32Array(128), new Float32Array(128)];
      assert.equal(limiter.process([[left, right]], [output]), true);
      for (let i = 0; i < 128; i++) {
        assert.ok(Math.abs(output[0][i]) <= 0.891251);
        assert.ok(Math.abs(output[1][i] - output[0][i] * 0.25) < 1e-6);
        if (Math.abs(output[0][i]) > 0.1 && Math.abs(output[0][i]) < 0.88) shaped++;
      }
    }
    assert.ok(shaped > 3000);
    limiter.port.onmessage({ data: { reset: true } });
    for (let block = 0; block < 4; block++) {
      const output = [new Float32Array(128), new Float32Array(128)];
      limiter.process([[]], [output]);
      assert.ok(output.every(channel => channel.every(s => s === 0)));
    }

    // 前瞻衰减必须形成斜坡，避免突降增益在原有背景声上制造咔嗒声。
    limiter.reset();
    const warmup = [new Float32Array(480), new Float32Array(480)];
    limiter.process([[new Float32Array(480).fill(0.1)]], [warmup]);
    const ramp = [new Float32Array(240), new Float32Array(240)];
    limiter.process([[new Float32Array(240).fill(4)]], [ramp]);
    let previous = 0.1;
    for (const value of ramp[0]) {
      assert.ok(Math.abs(value - previous) <= 0.1 / 240 + 1e-6);
      previous = value;
    }
    assert.ok(previous < 0.03);
  });
}
