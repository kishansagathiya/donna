import React, { useEffect, useRef } from 'react';
import {
  Animated,
  Easing,
  Pressable,
  StyleSheet,
  View,
} from 'react-native';

export type MicState =
  | 'idle'
  | 'requesting'
  | 'listening'
  | 'processing'
  | 'error';

const CORE_SIZE = 88;
const WRAPPER_SIZE = 160;
const RING_COUNT = 3;
const RING_STAGGER_MS = 200;
const PULSE_DURATION_MS = 1400;

/** Dark antique gold — button & pulse rings */
const GOLD_CORE = '#9A7B2F';
const GOLD_RING = '#B89446';
type MicButtonProps = {
  state: MicState;
  onPress: () => void;
  disabled?: boolean;
};

function createRingValues() {
  return Array.from({ length: RING_COUNT }, () => ({
    scale: new Animated.Value(1),
    opacity: new Animated.Value(0.45),
  }));
}

function resetRing(ring: { scale: Animated.Value; opacity: Animated.Value }) {
  ring.scale.setValue(1);
  ring.opacity.setValue(0.45);
}

function buildRingPulse(ring: {
  scale: Animated.Value;
  opacity: Animated.Value;
}) {
  return Animated.sequence([
    Animated.parallel([
      Animated.timing(ring.scale, {
        toValue: 1.9,
        duration: PULSE_DURATION_MS,
        easing: Easing.out(Easing.ease),
        useNativeDriver: true,
      }),
      Animated.timing(ring.opacity, {
        toValue: 0,
        duration: PULSE_DURATION_MS,
        easing: Easing.out(Easing.ease),
        useNativeDriver: true,
      }),
    ]),
    Animated.parallel([
      Animated.timing(ring.scale, {
        toValue: 1,
        duration: 0,
        useNativeDriver: true,
      }),
      Animated.timing(ring.opacity, {
        toValue: 0.45,
        duration: 0,
        useNativeDriver: true,
      }),
    ]),
  ]);
}

export function MicButton({ state, onPress, disabled }: MicButtonProps) {
  const ringsRef = useRef(createRingValues());
  const ringLoopsRef = useRef<Animated.CompositeAnimation[]>([]);
  const breatheLoopRef = useRef<Animated.CompositeAnimation | null>(null);
  const coreScale = useRef(new Animated.Value(1)).current;
  const coreOpacity = useRef(new Animated.Value(1)).current;

  const isListening = state === 'listening' || state === 'processing';
  const isRequesting = state === 'requesting';
  const accessibilityLabel =
    state === 'listening' || state === 'processing'
      ? 'Stop listening'
      : 'Start listening';

  useEffect(() => {
    const rings = ringsRef.current;
    ringLoopsRef.current.forEach(loop => loop.stop());
    ringLoopsRef.current = [];
    rings.forEach(resetRing);

    if (!isListening) {
      breatheLoopRef.current?.stop();
      breatheLoopRef.current = null;
      coreScale.setValue(1);
      return;
    }

    const staggerTimeouts: ReturnType<typeof setTimeout>[] = [];
    ringLoopsRef.current = rings.map((ring, index) => {
      const loop = Animated.loop(buildRingPulse(ring));
      staggerTimeouts.push(
        setTimeout(() => loop.start(), index * RING_STAGGER_MS),
      );
      return loop;
    });

    breatheLoopRef.current = Animated.loop(
      Animated.sequence([
        Animated.timing(coreScale, {
          toValue: 1.04,
          duration: 900,
          easing: Easing.inOut(Easing.ease),
          useNativeDriver: true,
        }),
        Animated.timing(coreScale, {
          toValue: 1,
          duration: 900,
          easing: Easing.inOut(Easing.ease),
          useNativeDriver: true,
        }),
      ]),
    );
    breatheLoopRef.current.start();

    return () => {
      staggerTimeouts.forEach(clearTimeout);
      ringLoopsRef.current.forEach(loop => loop.stop());
      ringLoopsRef.current = [];
      rings.forEach(resetRing);
      breatheLoopRef.current?.stop();
      breatheLoopRef.current = null;
      coreScale.setValue(1);
    };
  }, [isListening, coreScale]);

  useEffect(() => {
    if (!isRequesting) {
      coreOpacity.setValue(1);
      return;
    }

    const pulse = Animated.sequence([
      Animated.timing(coreOpacity, {
        toValue: 0.55,
        duration: 400,
        useNativeDriver: true,
      }),
      Animated.timing(coreOpacity, {
        toValue: 1,
        duration: 400,
        useNativeDriver: true,
      }),
    ]);
    pulse.start();
    return () => pulse.stop();
  }, [isRequesting, coreOpacity]);

  const accentColor = GOLD_RING;

  return (
    <View style={styles.wrapper} testID="mic-toggle">
      {isListening &&
        ringsRef.current.map((ring, index) => (
          <Animated.View
            key={index}
            pointerEvents="none"
            style={[
              styles.ring,
              {
                borderColor: accentColor,
                opacity: ring.opacity,
                transform: [{ scale: ring.scale }],
              },
            ]}
          />
        ))}
      <Pressable
        onPress={onPress}
        disabled={disabled}
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        accessibilityState={{ disabled: !!disabled, busy: isRequesting }}
        style={({ pressed }) => [pressed && styles.corePressed]}
      >
        <Animated.View
          style={[
            styles.core,
            isListening && styles.coreListening,
            {
              opacity: coreOpacity,
              transform: [{ scale: isListening ? coreScale : 1 }],
            },
          ]}
        />
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    width: WRAPPER_SIZE,
    height: WRAPPER_SIZE,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ring: {
    position: 'absolute',
    width: CORE_SIZE,
    height: CORE_SIZE,
    borderRadius: CORE_SIZE / 2,
    borderWidth: 2,
    backgroundColor: 'transparent',
  },
  core: {
    width: CORE_SIZE,
    height: CORE_SIZE,
    borderRadius: CORE_SIZE / 2,
    backgroundColor: GOLD_CORE,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: GOLD_RING,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.25,
    shadowRadius: 8,
    elevation: 6,
  },
  coreListening: {
    shadowOpacity: 0.4,
    shadowRadius: 12,
  },
  corePressed: {
    opacity: 0.85,
  },
});
