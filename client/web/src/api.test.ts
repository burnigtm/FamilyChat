import { beforeEach, describe, expect, it, vi } from 'vitest';

import { ApiClient, buildRealtimeUrl } from './api';

const fetchMock = vi.fn();

describe('ApiClient', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', fetchMock);
  });

  it('sends auth headers and device bootstrap payloads', async () => {
    fetchMock.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          userId: 'user-1',
          deviceId: 'device-1',
          registrationToken: 'token-1',
          displayName: 'Ava',
          deviceLabel: 'Desk',
        }),
        {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        },
      ),
    );

    const client = new ApiClient({
      userId: 'user-1',
      deviceId: 'device-1',
      registrationToken: 'token-1',
      displayName: 'Ava',
      deviceLabel: 'Desk',
    });

    await client.registerDevice({
      displayName: 'Ava',
      deviceLabel: 'Desk',
      prekeyBundle: { algorithm: 'ecdh-p256-hkdf-sha256' },
    });

    expect(fetchMock).toHaveBeenCalledWith(
      '/v1/devices/register',
      expect.objectContaining({
        method: 'POST',
        headers: expect.any(Headers),
      }),
    );

    const headers = fetchMock.mock.calls[0]?.[1]?.headers as Headers;
    expect(headers.get('Accept')).toBe('application/json');
    expect(headers.get('Content-Type')).toBe('application/json');
    expect(headers.get('Authorization')).toBe('Bearer token-1');

    const body = JSON.parse(fetchMock.mock.calls[0]?.[1]?.body as string);
    expect(body).toMatchObject({
      display_name: 'Ava',
      device_label: 'Desk',
      platform: 'web',
      prekey_bundle: { algorithm: 'ecdh-p256-hkdf-sha256' },
    });
  });

  it('parses JSON error payloads into thrown errors', async () => {
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify({ error: 'bad request' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    const client = new ApiClient(null);

    await expect(client.bootstrap()).rejects.toThrow('bad request');
  });

  it('builds a websocket url from the current page location by default', () => {
    const url = buildRealtimeUrl({
      userId: 'user-1',
      deviceId: 'device-1',
      registrationToken: 'token-1',
      displayName: 'Ava',
      deviceLabel: 'Desk',
    });

    expect(url).toContain('/ws?token=token-1');
    expect(url.startsWith('ws://') || url.startsWith('wss://')).toBe(true);
  });
});
