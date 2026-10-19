import { useEffect, useState } from 'react';
import { Keyboard, Platform } from 'react-native';

/** Whether the on-screen keyboard is showing (Will* events on iOS for snappier UI, Did* on Android). */
export function useKeyboardVisible(onShow?: () => void): boolean {
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    const showEvt = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvt = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';
    const s1 = Keyboard.addListener(showEvt, () => setVisible(true));
    const s2 = Keyboard.addListener(hideEvt, () => setVisible(false));
    const s3 = onShow ? Keyboard.addListener('keyboardDidShow', onShow) : null;
    return () => {
      s1.remove();
      s2.remove();
      s3?.remove();
    };
  }, [onShow]);
  return visible;
}
