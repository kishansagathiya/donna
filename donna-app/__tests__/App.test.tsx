/**
 * @format
 */

jest.mock('react-native-permissions', () => ({
  __esModule: true,
  check: jest.fn().mockResolvedValue('granted'),
  request: jest.fn().mockResolvedValue('granted'),
  PERMISSIONS: {
    IOS: { MICROPHONE: 'ios.permission.RECORD_AUDIO' },
    ANDROID: { RECORD_AUDIO: 'android.permission.RECORD_AUDIO' },
  },
  RESULTS: {
    GRANTED: 'granted',
    DENIED: 'denied',
    BLOCKED: 'blocked',
    UNAVAILABLE: 'unavailable',
    LIMITED: 'limited',
  },
}));

import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import App from '../App';

test('renders correctly', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });
});
