import { cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import { afterEach, beforeEach, vi } from 'vitest';

if (!window.crypto) {
  Object.defineProperty(window, 'crypto', {
    value: globalThis.crypto,
    configurable: true,
  });
}

Object.defineProperty(window, 'scrollTo', {
  value: vi.fn(),
  writable: true,
});

beforeEach(() => {
  window.localStorage.clear();
});

afterEach(() => {
  cleanup();
  window.localStorage.clear();
});
