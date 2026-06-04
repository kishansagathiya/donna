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
import { MicButton, type MicState } from './src/components/MicButton';

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
  const isDarkMode = useColorScheme() === 'dark';
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
      if (result === RESULTS.UNAVAILABLE) {
        setState('error');
        setErrorMsg(
          'Microphone permission is unavailable. Rebuild the iOS app (pod install).',
        );
        return;
      }
      if (result !== RESULTS.GRANTED) {
        setState('error');
        setErrorMsg(
          result === RESULTS.BLOCKED
            ? 'Microphone access blocked. Enable it in Settings.'
            : 'Microphone permission denied',
        );
        return;
      }
      // TODO: start native recording here once a compatible library is chosen
      setState('listening');
    } catch (e: unknown) {
      setState('error');
      setErrorMsg(e instanceof Error ? e.message : 'Failed to start');
    }
  };

  const statusText =
    state === 'error' ? (errorMsg ?? 'Something went wrong') : null;

  return (
    <View
      style={[
        styles.container,
        isDarkMode && styles.containerDark,
        {
          paddingTop: safeAreaInsets.top,
          paddingBottom: safeAreaInsets.bottom,
        },
      ]}
    >
      <MicButton
        state={state}
        onPress={toggleTalk}
        disabled={state === 'requesting'}
      />
      {statusText ? (
        <Text style={[styles.status, isDarkMode && styles.statusDark]}>
          {statusText}
        </Text>
      ) : null}
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
  containerDark: {
    backgroundColor: '#000000',
  },
  status: {
    marginTop: 16,
    color: '#666666',
    fontSize: 14,
  },
  statusDark: {
    color: '#aaaaaa',
  },
});

export default App;
