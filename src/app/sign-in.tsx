import { router } from 'expo-router';
import { useRef, useState } from 'react';
import { Pressable, Text, type TextInputInstance } from 'react-native';

import { AuthLayout, authStyles, validateEmail } from '@/components/AuthForm';
import { Button, TextField } from '@/components/ui';
import { errorMessage } from '@/lib/api';
import { useSession } from '@/state/session';

export default function SignInScreen() {
  const { signIn } = useSession();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<{ email?: string | null; password?: string | null }>({});
  const passwordRef = useRef<TextInputInstance>(null);

  const submit = async () => {
    const errs = { email: validateEmail(email), password: password ? null : 'Enter your password.' };
    setFieldErrors(errs);
    if (errs.email || errs.password) return;
    setSubmitting(true);
    setError(null);
    try {
      await signIn(email, password);
      // Stack.Protected switches to Home once the session is signed in.
    } catch (e) {
      setError(errorMessage(e));
      setSubmitting(false);
    }
  };

  return (
    <AuthLayout
      subtitle="Sign in to your notes"
      error={error}
      footer={
        <>
          <Text style={authStyles.footerText}>New to remai?</Text>
          <Pressable onPress={() => router.replace('/sign-up')} accessibilityRole="link" hitSlop={8}>
            <Text style={authStyles.link}>Create an account</Text>
          </Pressable>
        </>
      }
    >
      <TextField
        label="Email"
        value={email}
        onChangeText={setEmail}
        error={fieldErrors.email}
        autoCapitalize="none"
        autoCorrect={false}
        autoComplete="email"
        keyboardType="email-address"
        textContentType="username"
        returnKeyType="next"
        onSubmitEditing={() => passwordRef.current?.focus()}
        submitBehavior="submit"
        placeholder="you@example.com"
      />
      <TextField
        ref={passwordRef}
        label="Password"
        value={password}
        onChangeText={setPassword}
        error={fieldErrors.password}
        secureTextEntry
        autoCapitalize="none"
        autoComplete="current-password"
        textContentType="password"
        returnKeyType="go"
        onSubmitEditing={() => void submit()}
      />
      <Button title="Sign in" onPress={() => void submit()} loading={submitting} />
    </AuthLayout>
  );
}
