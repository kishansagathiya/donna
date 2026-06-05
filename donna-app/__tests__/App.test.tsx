/**
 * @format
 */

jest.mock('react-native-safe-area-context', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    SafeAreaProvider: ({ children }: { children: React.ReactNode }) => (
      <View>{children}</View>
    ),
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
  };
});

jest.mock('../src/hooks/useVoiceSession', () => ({
  useVoiceSession: () => ({
    state: 'idle',
    toggleTalk: jest.fn(),
    statusText: null,
    disabled: false,
  }),
}));

import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import App from '../App';

test('renders correctly', async () => {
  let tree: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    tree = ReactTestRenderer.create(<App />);
  });
  expect(tree!.root.findByProps({ testID: 'mic-toggle' })).toBeTruthy();
  const json = JSON.stringify(tree!.toJSON());
  expect(json).not.toContain('Talk to Donna');
});
