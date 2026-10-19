import { router } from 'expo-router';
import { useRef, useState } from 'react';
import { Pressable, Text, type TextInputInstance } from 'react-native';

import { AuthLayout, authStyles, validateRegistration } from '@/components/AuthForm';
import { Button, TextField } from '@/components/ui';
import { errorMessage, isApiError } from '@/lib/api';
import { useSession } from '@/state/session';

type FieldErrors = { name?: string | null; email?: string | null; password?: string | null };

export default function SignUpScreen() {
  const { signUp } = useSession();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const emailRef = useRef<TextInputInstance>(null);
  const passwordRef = useRef<TextInputInstance>(null);

  const submit = async () => {
    const errs = validateRegistration(name, email, password);
    setFieldErrors(errs);
    if (errs.name || errs.email || errs.password) return;
    setSubmitting(true);
    setError(null);
    try {
      await signUp(email, name, password);
    } catch (e) {
      if (isApiError(e) && e.code === 'email_taken') {
        setFieldErrors({ email: 'An account with this email already exists.' });
      } else {
        setError(errorMessage(e));
      }
      setSubmitting(false);
    }
  };

  return (
    <AuthLayout
      subtitle="Create your account"
      error={error}
      footer={
        <>
          <Text style={authStyles.footerText}>Already have an account?</Text>
          <Pressable onPress={() => router.replace('/sign-in')} accessibilityRole="link" hitSlop={8}>
            <Text style={authStyles.link}>Sign in</Text>
          </Pressable>
        </>
      }
    >
      <TextField
        label="Name"
        value={name}
        onChangeText={setName}
        error={fieldErrors.name}
        autoComplete="name"
        textContentType="name"
        maxLength={80}
        returnKeyType="next"
        submitBehavior="submit"
        onSubmitEditing={() => emailRef.current?.focus()}
        placeholder="Ada Lovelace"
      />
      <TextField
        ref={emailRef}
        label="Email"
        value={email}
        onChangeText={setEmail}
        error={fieldErrors.email}
        autoCapitalize="none"
        autoCorrect={false}
        autoComplete="email"
        keyboardType="email-address"
        textContentType="emailAddress"
        returnKeyType="next"
        submitBehavior="submit"
        onSubmitEditing={() => passwordRef.current?.focus()}
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
        autoComplete="new-password"
        textContentType="newPassword"
        maxLength={72}
        returnKeyType="go"
        onSubmitEditing={() => void submit()}
        placeholder="At least 8 characters"
      />
      <Button title="Create account" onPress={() => void submit()} loading={submitting} />
    </AuthLayout>
  );
}
