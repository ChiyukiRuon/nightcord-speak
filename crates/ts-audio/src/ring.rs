//! A lock-free single-producer single-consumer sample ring.
//!
//! Playback hands samples from a normal task to the audio callback, which must
//! never block: taking a mutex there risks a priority inversion that shows up
//! as a dropout. A ring with atomic indices lets the writer spin briefly and the
//! reader drop samples when it is starved — dropping is always better than
//! stalling the device.
//!
//! Capacity is rounded up to a power of two so wrapping is a mask rather than a
//! modulo, which matters when this runs 48 000 times a second.

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

/// The shared half of a ring.
struct Shared {
    /// Total samples consumed. Only ever advances.
    read: AtomicU64,
    /// Total samples written. Only ever advances.
    write: AtomicU64,
    capacity: u64,
}

/// One ring slot; `f32` has no invalid bit pattern, so no `Option` is needed.
struct Slot(std::cell::UnsafeCell<f32>);

// Safety: the producer only touches slots between `write` and `read`, and the
// consumer only touches slots between `read` and `write`. The two index pairs
// never overlap, so no slot is ever accessed from both sides at once.
unsafe impl Send for Slot {}
unsafe impl Sync for Slot {}

/// Writes samples into a [`SampleRing`].
pub struct SampleProducer {
    shared: Arc<Shared>,
    slots: Arc<[Slot]>,
}

/// Reads samples out of a [`SampleRing`].
pub struct SampleConsumer {
    shared: Arc<Shared>,
    slots: Arc<[Slot]>,
}

/// A bounded ring of `f32` samples.
pub struct SampleRing;

impl SampleRing {
    /// Creates a ring holding at least `capacity` samples, and returns the two
    /// ends.
    ///
    /// The producer side belongs on the writer's thread; the consumer side is
    /// meant to live inside an audio callback.
    ///
    /// Named after [`std::sync::mpsc::channel`] rather than `new`, since it
    /// hands back a pair rather than a `SampleRing`.
    #[must_use]
    pub fn channel(capacity: usize) -> (SampleProducer, SampleConsumer) {
        // At least 2 so the full/empty tests stay unambiguous, and a power of
        // two so the wrap is a mask.
        let capacity = capacity.max(2).next_power_of_two() as u64;

        let shared = Arc::new(Shared {
            read: AtomicU64::new(0),
            write: AtomicU64::new(0),
            capacity,
        });

        // `Arc<[Slot]>` so both ends index the *same* allocation; cloning the
        // box would give each end its own buffer and silently break the ring.
        let slots: Arc<[Slot]> = (0..capacity as usize)
            .map(|_| Slot(std::cell::UnsafeCell::new(0.0)))
            .collect();

        (
            SampleProducer {
                shared: Arc::clone(&shared),
                slots: Arc::clone(&slots),
            },
            SampleConsumer { shared, slots },
        )
    }
}

impl SampleProducer {
    /// How many samples can be written without overwriting unread data.
    #[must_use]
    pub fn space(&self) -> usize {
        let read = self.shared.read.load(Ordering::Acquire);
        let write = self.shared.write.load(Ordering::Relaxed);
        (self.shared.capacity - (write - read)) as usize
    }

    /// How many samples are queued but not yet read.
    #[must_use]
    pub fn buffered(&self) -> usize {
        let read = self.shared.read.load(Ordering::Acquire);
        let write = self.shared.write.load(Ordering::Relaxed);
        (write - read) as usize
    }

    /// The ring's total size in samples.
    #[must_use]
    pub fn capacity(&self) -> usize {
        self.shared.capacity as usize
    }

    /// Writes as many of `samples` as fit, returning how many were written.
    ///
    /// A short write is not an error: it means the consumer is behind, and the
    /// caller decides whether to retry or drop the remainder.
    pub fn write(&self, samples: &[f32]) -> usize {
        let read = self.shared.read.load(Ordering::Acquire);
        let write = self.shared.write.load(Ordering::Relaxed);
        let capacity = self.shared.capacity;

        let free = capacity - (write - read);
        let count = free.min(samples.len() as u64) as usize;

        for (offset, sample) in samples.iter().take(count).enumerate() {
            let index = ((write + offset as u64) & (capacity - 1)) as usize;
            // Safety: this slot is between `write` and `read`, so the consumer
            // cannot be touching it.
            unsafe {
                *self.slots[index].0.get() = *sample;
            }
        }

        self.shared
            .write
            .store(write + count as u64, Ordering::Release);
        count
    }

    /// Drops everything not yet read, as after a device switch.
    pub fn clear(&self) {
        let write = self.shared.write.load(Ordering::Relaxed);
        self.shared.read.store(write, Ordering::Release);
    }
}

impl SampleConsumer {
    /// How many samples are ready to read.
    #[must_use]
    pub fn available(&self) -> usize {
        let write = self.shared.write.load(Ordering::Acquire);
        let read = self.shared.read.load(Ordering::Relaxed);
        (write - read) as usize
    }

    /// Fills `out` with samples, returning how many were available.
    ///
    /// Whatever is not written is left untouched, so the caller can decide
    /// whether to output silence or repeat the last frame. **Never blocks**,
    /// which is the whole point: this runs in the audio callback.
    pub fn read(&self, out: &mut [f32]) -> usize {
        let write = self.shared.write.load(Ordering::Acquire);
        let read = self.shared.read.load(Ordering::Relaxed);
        let capacity = self.shared.capacity;

        let count = out.len().min((write - read) as usize);

        for (offset, slot) in out.iter_mut().take(count).enumerate() {
            let index = ((read + offset as u64) & (capacity - 1)) as usize;
            // Safety: this slot is between `read` and `write`, so the producer
            // cannot be touching it.
            *slot = unsafe { *self.slots[index].0.get() };
        }

        self.shared
            .read
            .store(read + count as u64, Ordering::Release);
        count
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_samples_in_order() {
        let (producer, consumer) = SampleRing::channel(8);
        let input: Vec<f32> = (0..8).map(|i| i as f32).collect();
        assert_eq!(producer.write(&input), 8);

        let mut output = vec![0.0; 8];
        assert_eq!(consumer.read(&mut output), 8);
        assert_eq!(output, input);
    }

    #[test]
    fn a_write_never_overwrites_unread_data() {
        let (producer, consumer) = SampleRing::channel(4);
        assert_eq!(producer.write(&[1.0, 2.0, 3.0, 4.0]), 4);
        assert_eq!(producer.space(), 0);

        // Full: the extra sample must be refused, not silently clobber sample 1.
        assert_eq!(producer.write(&[9.0]), 0);

        let mut output = vec![0.0; 4];
        assert_eq!(consumer.read(&mut output), 4);
        assert_eq!(output, [1.0, 2.0, 3.0, 4.0], "unread data was overwritten");
    }

    #[test]
    fn a_short_write_reports_what_it_took() {
        let (producer, _consumer) = SampleRing::channel(4);
        assert_eq!(producer.write(&[1.0, 2.0, 3.0, 4.0, 5.0, 6.0]), 4);
    }

    #[test]
    fn a_starved_read_reports_what_it_got() {
        let (producer, consumer) = SampleRing::channel(8);
        producer.write(&[1.0, 2.0]);

        let mut output = [0.0; 8];
        assert_eq!(consumer.read(&mut output), 2);
        assert_eq!(output[..2], [1.0, 2.0]);
        // The rest is left alone so the caller can pad it.
        assert_eq!(output[2..], [0.0; 6]);
    }

    #[test]
    fn reading_an_empty_ring_yields_nothing() {
        let (_producer, consumer) = SampleRing::channel(8);
        let mut output = [0.0; 4];
        assert_eq!(consumer.read(&mut output), 0);
    }

    #[test]
    fn indices_wrap_without_losing_order() {
        // Write and read past the capacity several times over, which is where
        // an off-by-one in the mask would show up.
        let (producer, consumer) = SampleRing::channel(4);
        let mut seen = Vec::new();

        for block in 0..10 {
            let input: Vec<f32> = (0..3).map(|i| (block * 3 + i) as f32).collect();
            assert_eq!(producer.write(&input), 3, "block {block}");

            let mut output = vec![0.0; 3];
            assert_eq!(consumer.read(&mut output), 3, "block {block}");
            seen.extend_from_slice(&output);
        }

        let expected: Vec<f32> = (0..30).map(|i| i as f32).collect();
        assert_eq!(seen, expected);
    }

    #[test]
    fn space_and_available_agree() {
        let (producer, consumer) = SampleRing::channel(16);
        assert_eq!(producer.space(), 16);
        assert_eq!(consumer.available(), 0);

        producer.write(&[0.0; 5]);
        assert_eq!(producer.space(), 11);
        assert_eq!(consumer.available(), 5);

        let mut output = [0.0; 5];
        consumer.read(&mut output);
        assert_eq!(producer.space(), 16);
        assert_eq!(consumer.available(), 0);
    }

    #[test]
    fn clear_discards_pending_samples() {
        // What a device switch does: stale audio must not be played afterwards.
        let (producer, consumer) = SampleRing::channel(8);
        producer.write(&[1.0, 2.0, 3.0]);
        producer.clear();

        assert_eq!(consumer.available(), 0);
        let mut output = [0.0; 4];
        assert_eq!(consumer.read(&mut output), 0);
    }

    #[test]
    fn capacity_is_rounded_up_to_a_power_of_two() {
        let (producer, _consumer) = SampleRing::channel(5);
        assert_eq!(producer.space(), 8);
    }

    #[test]
    fn a_degenerate_capacity_still_works() {
        // The caller asking for nothing must not produce a zero-sized buffer.
        let (producer, consumer) = SampleRing::channel(0);
        assert!(producer.write(&[1.0]) > 0);

        let mut output = [0.0; 1];
        assert_eq!(consumer.read(&mut output), 1);
        assert_eq!(output[0], 1.0);
    }
}
