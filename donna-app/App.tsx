/**
 * Donna — single-button microphone UI
 *
 * Tap to request mic permission and toggle a "listening" state.
 * Native recording is stubbed out (react-native-audio-recorder-player is
 * incompatible with RN 0.85.3 + New Architecture; will be replaced later).
 *
 * @format
 */

import React, { useState } from 'react';
import {
  Platform,
  Pressable,
  StatusBar,
  StyleSheet,
  Text,
  View,
  useColorScheme,
} from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import {
  check,
  PERMISSIONS,
  request,
  RESULTS,
} from 'react-native-permissions';

type MicState = 'idle' | 'requesting' | 'listening' | 'error';

function getMicPermission() {
  return Platform.OS === 'ios'
    ? PERMISSIONS.IOS.MICROPHONE
    : PERMISSIONS.ANDROID.RECORD_AUDIO;
}

function App() {
  const isDarkMode = useColorScheme() === 'dark';

  return (
    <SafeAreaProvider>
      <StatusBar barStyle={isDarkMode ? 'light-content' : 'dark-content'} />
      <AppContent />
    </SafeAreaProvider>
  );
}

function AppContent() {
  const safeAreaInsets = useSafeAreaInsets();
  const [state, setState] = useState<MicState>('idle');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const toggleTalk = async () => {
    if (state === 'listening') {
      setState('idle');
      setErrorMsg(null);
      return;
    }

    if (state === 'requesting') {
      return;
    }

    setState('requesting');
    setErrorMsg(null);
    try {
      const permission = getMicPermission();
      let result = await check(permission);
      if (result !== RESULTS.GRANTED) {
        result = await request(permission);
      }
      if (result !== RESULTS.GRANTED) {
        setState('error');
        setErrorMsg('Microphone permission denied');
        return;
      }
      // TODO: start native recording here once a compatible library is chosen
      setState('listening');
    } catch (e: unknown) {
      setState('error');
      setErrorMsg(e instanceof Error ? e.message : 'Failed to start');
    }
  };

  const label = state === 'listening' ? 'Stop' : 'Talk to Donna';
  const statusText =
    state === 'listening'
      ? 'Listening…'
      : state === 'error'
      ? errorMsg ?? 'Something went wrong'
      : null;

  return (
    <View
      style={[
        styles.container,
        {
          paddingTop: safeAreaInsets.top,
          paddingBottom: safeAreaInsets.bottom,
        },
      ]}
    >
      <Pressable
        onPress={toggleTalk}
        accessibilityRole="button"
        accessibilityLabel={label}
        testID="mic-toggle"
        style={({ pressed }) => [
          styles.button,
          state === 'listening' && styles.buttonActive,
          pressed && styles.buttonPressed,
        ]}
      >
        <Text style={styles.buttonLabel}>{label}</Text>
      </Pressable>
      {statusText ? <Text style={styles.status}>{statusText}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#ffffff',
  },
  button: {
    paddingVertical: 24,
    paddingHorizontal: 40,
    borderRadius: 32,
    backgroundColor: '#111111',
  },
  buttonActive: {
    backgroundColor: '#c0392b',
  },
  buttonPressed: {
    opacity: 0.7,
  },
  buttonLabel: {
    color: '#ffffff',
    fontSize: 20,
    fontWeight: '600',
  },
  status: {
    marginTop: 16,
    color: '#666666',
    fontSize: 14,
  },
});

export default App;
