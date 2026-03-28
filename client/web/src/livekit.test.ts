import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  deriveLiveKitKey: vi.fn(),
  setKey: vi.fn(),
  connect: vi.fn(),
  setE2EEEnabled: vi.fn(),
  startAudio: vi.fn(),
  setMicrophoneEnabled: vi.fn(),
  setCameraEnabled: vi.fn(),
  roomInstances: [] as Array<{ options: unknown; room: unknown }>,
}));

vi.mock('./crypto', () => ({
  deriveLiveKitKey: mocks.deriveLiveKitKey,
}));

vi.mock('livekit-client', () => {
  class ExternalE2EEKeyProvider {
    setKey = mocks.setKey;
  }

  class Room {
    localParticipant = {
      identity: 'device-1',
      name: 'Ava',
      isLocal: true,
      trackPublications: new Map(),
      setMicrophoneEnabled: mocks.setMicrophoneEnabled,
      setCameraEnabled: mocks.setCameraEnabled,
    };

    remoteParticipants = new Map();

    constructor(public readonly options: unknown) {
      mocks.roomInstances.push({ options, room: this });
    }

    connect = mocks.connect;
    setE2EEEnabled = mocks.setE2EEEnabled;
    startAudio = mocks.startAudio;
  }

  const Track = {
    Kind: {
      Video: 'video',
      Audio: 'audio',
    },
  };

  return {
    ExternalE2EEKeyProvider,
    Room,
    Track,
  };
});

import { connectEncryptedRoom, snapshotCallParticipants } from './livekit';

describe('livekit helpers', () => {
  beforeEach(() => {
    Object.values(mocks).forEach((value) => {
      if (typeof value === 'function' && 'mockReset' in value) {
        value.mockReset();
      }
    });

    mocks.roomInstances.length = 0;
    mocks.deriveLiveKitKey.mockResolvedValue(new Uint8Array([1, 2, 3, 4]));
    mocks.setKey.mockResolvedValue(undefined);
    mocks.connect.mockResolvedValue(undefined);
    mocks.setE2EEEnabled.mockResolvedValue(undefined);
    mocks.startAudio.mockResolvedValue(undefined);
    mocks.setMicrophoneEnabled.mockResolvedValue(undefined);
    mocks.setCameraEnabled.mockResolvedValue(undefined);

    vi.stubGlobal(
      'Worker',
      class MockWorker {
        constructor(public readonly url: URL) {}
      } as unknown as typeof Worker,
    );
  });

  it('returns only participants with visible or audible media plus the local user', () => {
    const videoTrack = { sid: 'video-1' };
    const audioTrack = { sid: 'audio-1' };

    const room = {
      localParticipant: {
        identity: 'device-1',
        name: 'Ava',
        isLocal: true,
        trackPublications: new Map(),
      },
      remoteParticipants: new Map([
        [
          'device-2',
          {
            identity: 'device-2',
            name: 'Dima',
            isLocal: false,
            trackPublications: new Map([
              ['video', { kind: 'video', track: videoTrack }],
              ['audio', { kind: 'audio', track: audioTrack }],
            ]),
          },
        ],
        [
          'device-3',
          {
            identity: 'device-3',
            name: 'Mila',
            isLocal: false,
            trackPublications: new Map(),
          },
        ],
      ]),
    };

    expect(snapshotCallParticipants(room as never)).toEqual([
      {
        identity: 'device-1',
        displayName: 'Ava',
        isLocal: true,
        videoTrack: null,
        audioTrack: null,
      },
      {
        identity: 'device-2',
        displayName: 'Dima',
        isLocal: false,
        videoTrack,
        audioTrack,
      },
    ]);
  });

  it('derives the room key and enables encrypted media before returning the room', async () => {
    const joinPayload = {
      conversationId: 'conv-1',
      roomName: 'familychat-room',
      roomTitle: 'Family HQ',
      serverUrl: 'wss://livekit.familychat.test',
      token: 'token-123',
      participantIdentity: 'device-1',
      participantName: 'Ava',
      keyGeneration: 2,
    };

    const room = await connectEncryptedRoom(joinPayload, 'conversation-key');
    const [{ options }] = mocks.roomInstances;

    expect(mocks.deriveLiveKitKey).toHaveBeenCalledWith(
      'conversation-key',
      'familychat-room',
    );
    expect(mocks.setKey).toHaveBeenCalledWith(new Uint8Array([1, 2, 3, 4]));
    expect(options).toMatchObject({
      adaptiveStream: true,
      dynacast: true,
      encryption: {
        keyProvider: expect.any(Object),
        worker: expect.any(Worker),
      },
    });
    expect(mocks.connect).toHaveBeenCalledWith(
      'wss://livekit.familychat.test',
      'token-123',
    );
    expect(mocks.setE2EEEnabled).toHaveBeenCalledWith(true);
    expect(mocks.startAudio).toHaveBeenCalledTimes(1);
    expect(mocks.setMicrophoneEnabled).toHaveBeenCalledWith(true);
    expect(mocks.setCameraEnabled).toHaveBeenCalledWith(true);
    expect(room).toBe(mocks.roomInstances[0]?.room);
  });
});
