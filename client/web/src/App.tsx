import {
  FormEvent,
  startTransition,
  useDeferredValue,
  useEffect,
  useRef,
  useState,
} from 'react';
import type { Room } from 'livekit-client';

import { ApiClient, buildRealtimeUrl } from './api';
import {
  createConversationRoomName,
  createDeviceKeyBundle,
  decryptMessageBody,
  encryptMessageBody,
  generateConversationKeyMaterial,
  unwrapRoomKeyPackage,
  wrapRoomKeyForDevices,
} from './crypto';
import {
  clearSessionState,
  loadConversationKeys,
  loadConversations,
  loadDeviceKeys,
  loadMessages,
  loadSelectedConversationId,
  loadSession,
  saveConversationKeys,
  saveConversations,
  saveDeviceKeys,
  saveMessages,
  saveSelectedConversationId,
  saveSession,
} from './storage';
import type {
  BootstrapPayload,
  ChatMessage,
  ConversationDetail,
  ConversationSummary,
  DirectoryDevice,
  DirectoryEntry,
  LinkingTokenPayload,
  RealtimeEvent,
  Session,
  StoredConversationKey,
  StoredDeviceKeyMaterial,
} from './types';
import type { CallParticipantView } from './livekit';

type ConnectionState = 'offline' | 'connecting' | 'online';
type CallStatus = 'idle' | 'joining' | 'joined' | 'error';

interface DecryptedMessageState {
  body: string;
  error: string | null;
}

interface CallState {
  status: CallStatus;
  room: Room | null;
  roomTitle: string | null;
  participants: CallParticipantView[];
  error: string | null;
}

const EMPTY_CALL_STATE: CallState = {
  status: 'idle',
  room: null,
  roomTitle: null,
  participants: [],
  error: null,
};

function conversationKeySlot(
  conversationId: string,
  keyGeneration: number | null,
) {
  if (keyGeneration === null) {
    return null;
  }

  return `${conversationId}:${keyGeneration}`;
}

function sortConversations(conversations: ConversationSummary[]) {
  return [...conversations].sort((left, right) => {
    const leftStamp = left.lastMessageAt ?? '';
    const rightStamp = right.lastMessageAt ?? '';
    return rightStamp.localeCompare(leftStamp);
  });
}

function mergeConversation(
  current: ConversationSummary[],
  incoming: ConversationSummary,
) {
  const next = current.filter((item) => item.id !== incoming.id);
  next.push(incoming);
  return sortConversations(next);
}

function mergeMessageList(
  current: Record<string, ChatMessage[]>,
  message: ChatMessage,
) {
  const list = current[message.conversationId] ?? [];
  if (list.some((item) => item.id === message.id)) {
    return current;
  }

  return {
    ...current,
    [message.conversationId]: [...list, message].sort((left, right) =>
      left.createdAt.localeCompare(right.createdAt),
    ),
  };
}

function formatClock(value: string | null) {
  if (!value) {
    return 'Fresh';
  }

  return new Intl.DateTimeFormat(undefined, {
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(value));
}

function formatStamp(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(value));
}

function formatExpiry(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    hour: 'numeric',
    minute: '2-digit',
    month: 'short',
    day: 'numeric',
  }).format(new Date(value));
}

function toErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  return 'Unexpected failure';
}

function collectConversationDevices(
  directory: DirectoryEntry[],
  userIds: string[],
) {
  const wanted = new Set(userIds);
  const seen = new Set<string>();
  const devices: DirectoryDevice[] = [];

  for (const entry of directory) {
    if (!wanted.has(entry.userId)) {
      continue;
    }

    for (const device of entry.devices) {
      if (seen.has(device.deviceId)) {
        continue;
      }

      devices.push(device);
      seen.add(device.deviceId);
    }
  }

  return devices;
}

function currentConversationKey(
  conversation: ConversationDetail | null,
  conversationKeys: Record<string, StoredConversationKey>,
) {
  if (!conversation) {
    return null;
  }

  const slot = conversationKeySlot(conversation.id, conversation.keyGeneration);
  return slot ? conversationKeys[slot] ?? null : null;
}

function ParticipantTile({
  participant,
}: {
  participant: CallParticipantView;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const audioRef = useRef<HTMLAudioElement>(null);

  useEffect(() => {
    const element = videoRef.current;
    if (!element || !participant.videoTrack) {
      return;
    }

    participant.videoTrack.attach(element);
    return () => {
      participant.videoTrack?.detach(element);
    };
  }, [participant.videoTrack]);

  useEffect(() => {
    const element = audioRef.current;
    if (!element || !participant.audioTrack) {
      return;
    }

    participant.audioTrack.attach(element);
    return () => {
      participant.audioTrack?.detach(element);
    };
  }, [participant.audioTrack]);

  const initials = participant.displayName
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('')
    .slice(0, 2);

  return (
    <article
      className={
        participant.isLocal ? 'call-participant is-local' : 'call-participant'
      }
    >
      {participant.videoTrack ? (
        <video ref={videoRef} autoPlay playsInline muted={participant.isLocal} />
      ) : (
        <div className="call-avatar">{initials || 'FC'}</div>
      )}
      <audio ref={audioRef} autoPlay muted={participant.isLocal} />
      <div className="call-label">
        <strong>{participant.displayName}</strong>
        <span>{participant.isLocal ? 'This browser' : 'Encrypted media'}</span>
      </div>
    </article>
  );
}

function App() {
  const [session, setSession] = useState<Session | null>(() => loadSession());
  const [conversations, setConversations] = useState<ConversationSummary[]>(
    () => loadConversations(),
  );
  const [messagesByConversation, setMessagesByConversation] = useState<
    Record<string, ChatMessage[]>
  >(() => loadMessages());
  const [selectedConversationId, setSelectedConversationId] = useState<
    string | null
  >(() => loadSelectedConversationId());
  const [conversationDetails, setConversationDetails] = useState<
    Record<string, ConversationDetail>
  >({});
  const [directory, setDirectory] = useState<DirectoryEntry[]>([]);
  const [deviceKeys, setDeviceKeys] = useState<
    Record<string, StoredDeviceKeyMaterial>
  >(() => loadDeviceKeys());
  const [conversationKeys, setConversationKeys] = useState<
    Record<string, StoredConversationKey>
  >(() => loadConversationKeys());
  const [decryptedMessages, setDecryptedMessages] = useState<
    Record<string, DecryptedMessageState>
  >({});
  const [registerForm, setRegisterForm] = useState({
    displayName: '',
    deviceLabel: 'Browser Desk',
  });
  const [linkForm, setLinkForm] = useState({
    linkingToken: '',
    deviceLabel: 'Linked Browser',
  });
  const [authMode, setAuthMode] = useState<'register' | 'link'>('register');
  const [draftMessage, setDraftMessage] = useState('');
  const [roomTitle, setRoomTitle] = useState('');
  const [roomMembers, setRoomMembers] = useState<string[]>([]);
  const [memberToAdd, setMemberToAdd] = useState('');
  const [linkToken, setLinkToken] = useState<LinkingTokenPayload | null>(null);
  const [statusText, setStatusText] = useState(
    'Register a browser device or link to an existing account.',
  );
  const [isRegistering, setIsRegistering] = useState(false);
  const [isGeneratingLinkToken, setIsGeneratingLinkToken] = useState(false);
  const [isBootstrapping, setIsBootstrapping] = useState(false);
  const [isConversationLoading, setIsConversationLoading] = useState(false);
  const [isSending, setIsSending] = useState(false);
  const [isCreatingRoom, setIsCreatingRoom] = useState(false);
  const [isAddingMember, setIsAddingMember] = useState(false);
  const [isJoiningCall, setIsJoiningCall] = useState(false);
  const [connectionState, setConnectionState] = useState<ConnectionState>('offline');
  const [socketRevision, setSocketRevision] = useState(0);
  const [searchQuery, setSearchQuery] = useState('');
  const [callState, setCallState] = useState<CallState>(EMPTY_CALL_STATE);
  const deferredSearch = useDeferredValue(searchQuery);
  const livekitModuleRef = useRef<null | typeof import('./livekit')>(null);

  const api = new ApiClient(session);

  useEffect(() => {
    saveSession(session);
  }, [session]);

  useEffect(() => {
    saveConversations(conversations);
  }, [conversations]);

  useEffect(() => {
    saveMessages(messagesByConversation);
  }, [messagesByConversation]);

  useEffect(() => {
    saveSelectedConversationId(selectedConversationId);
  }, [selectedConversationId]);

  useEffect(() => {
    saveDeviceKeys(deviceKeys);
  }, [deviceKeys]);

  useEffect(() => {
    saveConversationKeys(conversationKeys);
  }, [conversationKeys]);

  useEffect(() => {
    if (!session) {
      return;
    }

    let ignore = false;
    setIsBootstrapping(true);
    setStatusText('Syncing encrypted rooms and device directory...');

    api
      .bootstrap()
      .then((payload: BootstrapPayload) => {
        if (ignore) {
          return;
        }

        startTransition(() => {
          setSession(payload.session);
          setDirectory(payload.directory);
          setConversations(sortConversations(payload.conversations));
          setSelectedConversationId((current) => {
            if (
              current &&
              payload.conversations.some((item) => item.id === current)
            ) {
              return current;
            }

            return (
              payload.featuredConversationId ??
              payload.conversations[0]?.id ??
              null
            );
          });
        });

        setStatusText('End-to-end encrypted sync is live.');
      })
      .catch((error: unknown) => {
        if (!ignore) {
          setStatusText(`Bootstrap failed: ${toErrorMessage(error)}`);
        }
      })
      .finally(() => {
        if (!ignore) {
          setIsBootstrapping(false);
        }
      });

    return () => {
      ignore = true;
    };
  }, [session?.registrationToken]);

  useEffect(() => {
    if (!session) {
      setConnectionState('offline');
      return;
    }

    let shouldReconnect = true;
    let reconnectTimer: number | undefined;
    const websocket = new WebSocket(buildRealtimeUrl(session));
    setConnectionState('connecting');

    websocket.onopen = () => {
      setConnectionState('online');
    };

    websocket.onclose = () => {
      setConnectionState('offline');
      if (shouldReconnect) {
        reconnectTimer = window.setTimeout(() => {
          setSocketRevision((current) => current + 1);
        }, 2500);
      }
    };

    websocket.onerror = () => {
      websocket.close();
    };

    websocket.onmessage = (event) => {
      let payload: RealtimeEvent;

      try {
        payload = JSON.parse(event.data) as RealtimeEvent;
      } catch {
        return;
      }

      startTransition(() => {
        if (payload.conversation) {
          setConversations((current) =>
            mergeConversation(current, payload.conversation!),
          );
        }

        if (payload.message) {
          setMessagesByConversation((current) =>
            mergeMessageList(current, payload.message!),
          );
        }
      });
    };

    return () => {
      shouldReconnect = false;
      if (reconnectTimer) {
        window.clearTimeout(reconnectTimer);
      }
      websocket.close();
    };
  }, [session?.registrationToken, socketRevision]);

  useEffect(() => {
    if (!session || !selectedConversationId) {
      return;
    }

    let ignore = false;
    setIsConversationLoading(true);

    api
      .getConversationState(selectedConversationId)
      .then((payload) => {
        if (ignore) {
          return;
        }

        startTransition(() => {
          setConversationDetails((current) => ({
            ...current,
            [payload.conversation.id]: payload.conversation,
          }));
          setConversations((current) =>
            mergeConversation(current, payload.summary),
          );
          setMessagesByConversation((current) => ({
            ...current,
            [payload.summary.id]: payload.messages,
          }));
        });
      })
      .catch((error: unknown) => {
        if (!ignore) {
          setStatusText(`Conversation sync failed: ${toErrorMessage(error)}`);
        }
      })
      .finally(() => {
        if (!ignore) {
          setIsConversationLoading(false);
        }
      });

    return () => {
      ignore = true;
    };
  }, [selectedConversationId, session?.registrationToken]);

  useEffect(() => {
    if (!session || !selectedConversationId) {
      return;
    }

    const detail = conversationDetails[selectedConversationId];
    const deviceKey = deviceKeys[session.deviceId];

    if (!detail?.keyPackage || detail.keyGeneration === null) {
      return;
    }

    if (!deviceKey) {
      setStatusText(
        'This browser is missing its private device key. Register or relink it again.',
      );
      return;
    }

    const slot = conversationKeySlot(detail.id, detail.keyGeneration);
    if (!slot || conversationKeys[slot]) {
      return;
    }

    let ignore = false;

    unwrapRoomKeyPackage(detail.keyPackage, detail.roomName, deviceKey)
      .then((keyMaterial) => {
        if (ignore) {
          return;
        }

        startTransition(() => {
          setConversationKeys((current) => ({
            ...current,
            [slot]: {
              conversationId: detail.id,
              roomName: detail.roomName,
              keyGeneration: detail.keyGeneration!,
              keyMaterial,
            },
          }));
        });
      })
      .catch((error: unknown) => {
        if (!ignore) {
          setStatusText(
            `Room key unwrap failed: ${toErrorMessage(error)}`,
          );
        }
      });

    return () => {
      ignore = true;
    };
  }, [
    conversationDetails,
    conversationKeys,
    deviceKeys,
    selectedConversationId,
    session?.deviceId,
  ]);

  useEffect(() => {
    if (!selectedConversationId) {
      return;
    }

    const selectedMessages = messagesByConversation[selectedConversationId] ?? [];
    if (selectedMessages.length === 0) {
      return;
    }

    let ignore = false;

    Promise.all(
      selectedMessages.map(async (message) => {
        if (message.body) {
          return [
            message.id,
            {
              body: message.body,
              error: null,
            },
          ] as const;
        }

        if (!message.ciphertext || !message.nonce) {
          return [
            message.id,
            {
              body: 'Encrypted message',
              error: 'Missing ciphertext metadata',
            },
          ] as const;
        }

        const generation =
          message.senderKeyGeneration ??
          conversationDetails[selectedConversationId]?.keyGeneration;
        const slot = conversationKeySlot(selectedConversationId, generation);
        const key = slot ? conversationKeys[slot] : null;

        if (!key) {
          return [
            message.id,
            {
              body: 'Encrypted message',
              error: 'Room key not available on this device yet',
            },
          ] as const;
        }

        try {
          const body = await decryptMessageBody(
            key.keyMaterial,
            message.ciphertext,
            message.nonce,
          );
          return [message.id, { body, error: null }] as const;
        } catch (error: unknown) {
          return [
            message.id,
            {
              body: 'Unable to decrypt message',
              error: toErrorMessage(error),
            },
          ] as const;
        }
      }),
    ).then((entries) => {
      if (ignore) {
        return;
      }

      startTransition(() => {
        setDecryptedMessages((current) => ({
          ...current,
          ...Object.fromEntries(entries),
        }));
      });
    });

    return () => {
      ignore = true;
    };
  }, [conversationDetails, conversationKeys, messagesByConversation, selectedConversationId]);

  useEffect(() => {
    if (!callState.room) {
      return;
    }

    const room = callState.room;
    const syncParticipants = () => {
      const participants =
        livekitModuleRef.current?.snapshotCallParticipants(room) ?? [];
      startTransition(() => {
        setCallState((current) =>
          current.room === room
            ? {
                ...current,
                status: 'joined',
                participants,
              }
            : current,
        );
      });
    };
    const handleDisconnected = () => {
      setCallState((current) =>
        current.room === room ? EMPTY_CALL_STATE : current,
      );
      setStatusText('Call disconnected.');
    };

    syncParticipants();

    room.on('participantConnected', syncParticipants);
    room.on('participantDisconnected', syncParticipants);
    room.on('trackSubscribed', syncParticipants);
    room.on('trackUnsubscribed', syncParticipants);
    room.on('localTrackPublished', syncParticipants);
    room.on('localTrackUnpublished', syncParticipants);
    room.on('disconnected', handleDisconnected);

    return () => {
      room.off('participantConnected', syncParticipants);
      room.off('participantDisconnected', syncParticipants);
      room.off('trackSubscribed', syncParticipants);
      room.off('trackUnsubscribed', syncParticipants);
      room.off('localTrackPublished', syncParticipants);
      room.off('localTrackUnpublished', syncParticipants);
      room.off('disconnected', handleDisconnected);
    };
  }, [callState.room]);

  const filteredConversations = conversations.filter((conversation) => {
    if (!deferredSearch.trim()) {
      return true;
    }

    const needle = deferredSearch.toLowerCase();
    return (
      conversation.title.toLowerCase().includes(needle) ||
      (conversation.lastMessagePreview ?? '').toLowerCase().includes(needle)
    );
  });

  const availableContacts = session
    ? directory.filter((entry) => entry.userId !== session.userId)
    : [];
  const selectedConversation =
    conversations.find((item) => item.id === selectedConversationId) ?? null;
  const selectedDetail =
    (selectedConversationId && conversationDetails[selectedConversationId]) ||
    null;
  const selectedMessages =
    (selectedConversationId && messagesByConversation[selectedConversationId]) ||
    [];
  const selectedKey = currentConversationKey(selectedDetail, conversationKeys);
  const selectedMemberIds = new Set(
    selectedDetail?.members.map((member) => member.userId) ?? [],
  );
  const addableContacts = availableContacts.filter(
    (entry) => !selectedMemberIds.has(entry.userId),
  );

  async function leaveCall() {
    if (callState.room) {
      callState.room.disconnect();
    }

    setCallState(EMPTY_CALL_STATE);
    setStatusText('Left the encrypted call.');
  }

  async function handleRegister(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsRegistering(true);
    setStatusText(
      authMode === 'register'
        ? 'Creating browser device identity...'
        : 'Linking browser device...',
    );

    try {
      const bundle = await createDeviceKeyBundle();
      const nextSession =
        authMode === 'register'
          ? await api.registerDevice({
              displayName: registerForm.displayName,
              deviceLabel: registerForm.deviceLabel,
              prekeyBundle: bundle.publicBundle,
            })
          : await api.linkDevice({
              linkingToken: linkForm.linkingToken.trim(),
              deviceLabel: linkForm.deviceLabel,
              prekeyBundle: bundle.publicBundle,
            });

      if (callState.room) {
        callState.room.disconnect();
      }

      clearSessionState();
      setConversationDetails({});
      setMessagesByConversation({});
      setConversations([]);
      setSelectedConversationId(null);
      setSocketRevision(0);
      setDirectory([]);
      setLinkToken(null);
      setCallState(EMPTY_CALL_STATE);
      setDecryptedMessages({});
      setConversationKeys({});
      setDeviceKeys({
        [nextSession.deviceId]: bundle.material,
      });
      setSession(nextSession);
      setStatusText(
        authMode === 'register'
          ? 'Device registered. Pulling encrypted room state...'
          : 'Device linked. Pulling encrypted room state...',
      );
    } catch (error: unknown) {
      setStatusText(`Device setup failed: ${toErrorMessage(error)}`);
    } finally {
      setIsRegistering(false);
    }
  }

  async function handleGenerateLinkToken() {
    setIsGeneratingLinkToken(true);
    setStatusText('Creating a short-lived linking token...');

    try {
      const payload = await api.createLinkToken();
      setLinkToken(payload);
      setStatusText('Link token ready for the next browser.');
    } catch (error: unknown) {
      setStatusText(`Link token failed: ${toErrorMessage(error)}`);
    } finally {
      setIsGeneratingLinkToken(false);
    }
  }

  async function handleCreateConversation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!session) {
      return;
    }

    setIsCreatingRoom(true);
    setStatusText('Wrapping a new room key for every participant device...');

    try {
      const memberIds = [...roomMembers];
      const roomName = createConversationRoomName();
      const keyMaterial = generateConversationKeyMaterial();
      const devices = collectConversationDevices(directory, [
        session.userId,
        ...memberIds,
      ]);
      const wrappedKeys = await wrapRoomKeyForDevices(
        keyMaterial,
        roomName,
        devices,
      );
      const payload = await api.createConversation({
        title: roomTitle.trim(),
        roomName,
        conversationType: memberIds.length === 1 ? 'direct' : 'group',
        memberIds,
        wrappedKeys,
      });
      const keyGeneration = payload.conversation.keyGeneration ?? 1;
      const slot = conversationKeySlot(payload.conversation.id, keyGeneration);

      startTransition(() => {
        setConversationDetails((current) => ({
          ...current,
          [payload.conversation.id]: payload.conversation,
        }));
        setConversations((current) =>
          mergeConversation(current, payload.summary),
        );
        setMessagesByConversation((current) => ({
          ...current,
          [payload.summary.id]: current[payload.summary.id] ?? [],
        }));
        setSelectedConversationId(payload.summary.id);
        setConversationKeys((current) => ({
          ...current,
          ...(slot
            ? {
                [slot]: {
                  conversationId: payload.conversation.id,
                  roomName: payload.conversation.roomName,
                  keyGeneration,
                  keyMaterial,
                },
              }
            : {}),
        }));
      });

      setRoomTitle('');
      setRoomMembers([]);
      setStatusText(`Room "${payload.summary.title}" is encrypted and ready.`);
    } catch (error: unknown) {
      setStatusText(`Room creation failed: ${toErrorMessage(error)}`);
    } finally {
      setIsCreatingRoom(false);
    }
  }

  async function handleSendMessage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedConversationId || !draftMessage.trim() || !selectedKey) {
      return;
    }

    setIsSending(true);

    try {
      const encrypted = await encryptMessageBody(
        selectedKey.keyMaterial,
        draftMessage.trim(),
      );
      const payload = await api.sendMessage({
        conversationId: selectedConversationId,
        ciphertext: encrypted.ciphertext,
        nonce: encrypted.nonce,
        encryption: encrypted.encryption,
        senderKeyGeneration: selectedKey.keyGeneration,
      });

      startTransition(() => {
        setConversations((current) =>
          mergeConversation(current, payload.summary),
        );
        setMessagesByConversation((current) =>
          mergeMessageList(current, payload.message),
        );
      });

      setDraftMessage('');
      setStatusText(`Encrypted payload delivered to ${payload.queuedFor} device slot(s).`);
    } catch (error: unknown) {
      setStatusText(`Send failed: ${toErrorMessage(error)}`);
    } finally {
      setIsSending(false);
    }
  }

  async function handleJoinCall() {
    if (!selectedConversationId || !selectedKey) {
      return;
    }

    setIsJoiningCall(true);
    setStatusText('Joining LiveKit with the room E2EE key...');

    try {
      if (callState.room) {
        callState.room.disconnect();
      }

      const joinPayload = await api.joinCall(selectedConversationId);
      const livekitModule = await import('./livekit');
      livekitModuleRef.current = livekitModule;
      const room = await livekitModule.connectEncryptedRoom(
        joinPayload,
        selectedKey.keyMaterial,
      );

      setCallState({
        status: 'joined',
        room,
        roomTitle: joinPayload.roomTitle,
        participants: livekitModule.snapshotCallParticipants(room),
        error: null,
      });
      setStatusText('Encrypted call connected.');
    } catch (error: unknown) {
      setCallState({
        ...EMPTY_CALL_STATE,
        status: 'error',
        error: toErrorMessage(error),
      });
      setStatusText(`Call join failed: ${toErrorMessage(error)}`);
    } finally {
      setIsJoiningCall(false);
    }
  }

  async function handleAddMember(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedConversationId || !selectedDetail || !memberToAdd) {
      return;
    }

    setIsAddingMember(true);
    setStatusText('Rotating the room key for the new membership set...');

    try {
      const keyMaterial = generateConversationKeyMaterial();
      const userIds = [
        ...selectedDetail.members.map((member) => member.userId),
        memberToAdd,
      ];
      const wrappedKeys = await wrapRoomKeyForDevices(
        keyMaterial,
        selectedDetail.roomName,
        collectConversationDevices(directory, userIds),
      );
      const payload = await api.addMember({
        conversationId: selectedConversationId,
        userId: memberToAdd,
        wrappedKeys,
      });
      const keyGeneration = payload.conversation.keyGeneration ?? 1;
      const slot = conversationKeySlot(payload.conversation.id, keyGeneration);

      startTransition(() => {
        setConversationDetails((current) => ({
          ...current,
          [payload.conversation.id]: payload.conversation,
        }));
        setConversations((current) =>
          mergeConversation(current, payload.summary),
        );
        setConversationKeys((current) => ({
          ...current,
          ...(slot
            ? {
                [slot]: {
                  conversationId: payload.conversation.id,
                  roomName: payload.conversation.roomName,
                  keyGeneration,
                  keyMaterial,
                },
              }
            : {}),
        }));
      });

      setMemberToAdd('');
      setStatusText('Member added and the room key rotated.');
    } catch (error: unknown) {
      setStatusText(`Member add failed: ${toErrorMessage(error)}`);
    } finally {
      setIsAddingMember(false);
    }
  }

  function toggleRoomMember(userId: string) {
    setRoomMembers((current) =>
      current.includes(userId)
        ? current.filter((item) => item !== userId)
        : [...current, userId],
    );
  }

  function resetSession() {
    if (callState.room) {
      callState.room.disconnect();
    }

    clearSessionState();
    setSession(null);
    setDirectory([]);
    setConversations([]);
    setConversationDetails({});
    setMessagesByConversation({});
    setSelectedConversationId(null);
    setConnectionState('offline');
    setSocketRevision(0);
    setDeviceKeys({});
    setConversationKeys({});
    setDecryptedMessages({});
    setLinkToken(null);
    setCallState(EMPTY_CALL_STATE);
    setStatusText('Session cleared. Register or relink this browser to continue.');
  }

  if (!session) {
    return (
      <div className="welcome-shell">
        <section className="welcome-panel">
          <p className="eyebrow">FamilyChat Web</p>
          <h1>Encrypted rooms, linked browsers, and private calls.</h1>
          <p className="welcome-copy">
            The browser client now keeps its own device keypair, unwraps room
            secrets locally, and uses those same secrets to protect LiveKit
            audio and video.
          </p>

          <div className="auth-mode-tabs" role="tablist" aria-label="Device setup mode">
            <button
              type="button"
              className={authMode === 'register' ? 'mode-pill is-active' : 'mode-pill'}
              onClick={() => setAuthMode('register')}
            >
              Register first device
            </button>
            <button
              type="button"
              className={authMode === 'link' ? 'mode-pill is-active' : 'mode-pill'}
              onClick={() => setAuthMode('link')}
            >
              Link with token
            </button>
          </div>

          <form className="welcome-form" onSubmit={handleRegister}>
            {authMode === 'register' ? (
              <>
                <label>
                  <span>Display name</span>
                  <input
                    required
                    autoComplete="name"
                    value={registerForm.displayName}
                    onChange={(event) =>
                      setRegisterForm((current) => ({
                        ...current,
                        displayName: event.target.value,
                      }))
                    }
                    placeholder="Ava, Dima, Oma..."
                  />
                </label>

                <label>
                  <span>Device label</span>
                  <input
                    required
                    value={registerForm.deviceLabel}
                    onChange={(event) =>
                      setRegisterForm((current) => ({
                        ...current,
                        deviceLabel: event.target.value,
                      }))
                    }
                    placeholder="Kitchen laptop"
                  />
                </label>
              </>
            ) : (
              <>
                <label>
                  <span>Link token</span>
                  <input
                    required
                    value={linkForm.linkingToken}
                    onChange={(event) =>
                      setLinkForm((current) => ({
                        ...current,
                        linkingToken: event.target.value,
                      }))
                    }
                    placeholder="Paste the short-lived token"
                  />
                </label>

                <label>
                  <span>Device label</span>
                  <input
                    required
                    value={linkForm.deviceLabel}
                    onChange={(event) =>
                      setLinkForm((current) => ({
                        ...current,
                        deviceLabel: event.target.value,
                      }))
                    }
                    placeholder="Living room browser"
                  />
                </label>
              </>
            )}

            <button className="primary-button" disabled={isRegistering}>
              {isRegistering
                ? 'Provisioning device...'
                : authMode === 'register'
                  ? 'Register encrypted browser'
                  : 'Link encrypted browser'}
            </button>
          </form>

          <p className="status-line">{statusText}</p>
        </section>
      </div>
    );
  }

  return (
    <div className="shell">
      <aside className="sidebar">
        <header className="sidebar-head">
          <div>
            <p className="eyebrow">FamilyChat Web</p>
            <h1>Rooms</h1>
          </div>
          <span
            className={`connection-pill connection-${connectionState}`}
            aria-live="polite"
          >
            {connectionState}
          </span>
        </header>

        <label className="search-field">
          <span className="sr-only">Search rooms</span>
          <input
            value={searchQuery}
            onChange={(event) => setSearchQuery(event.target.value)}
            placeholder="Search rooms or encrypted previews"
          />
        </label>

        <nav className="conversation-list" aria-label="Conversation list">
          {filteredConversations.map((conversation) => (
            <button
              key={conversation.id}
              type="button"
              className={
                conversation.id === selectedConversationId
                  ? 'conversation-row is-active'
                  : 'conversation-row'
              }
              onClick={() =>
                startTransition(() => {
                  setSelectedConversationId(conversation.id);
                })
              }
            >
              <div className="conversation-row-top">
                <strong>{conversation.title}</strong>
                <span>{formatClock(conversation.lastMessageAt)}</span>
              </div>
              <p>{conversation.lastMessagePreview ?? 'No messages yet.'}</p>
              <div className="conversation-row-meta">
                <span>{conversation.memberCount} member(s)</span>
                <span>
                  key {conversation.keyGeneration ?? 0}
                </span>
              </div>
            </button>
          ))}
        </nav>

        <form className="new-room-form" onSubmit={handleCreateConversation}>
          <label>
            <span>Open an encrypted room</span>
            <input
              value={roomTitle}
              onChange={(event) => setRoomTitle(event.target.value)}
              placeholder="Optional title for a group room"
            />
          </label>

          <div className="member-picker">
            {availableContacts.map((entry) => (
              <label key={entry.userId} className="member-choice">
                <input
                  type="checkbox"
                  checked={roomMembers.includes(entry.userId)}
                  onChange={() => toggleRoomMember(entry.userId)}
                />
                <span>
                  <strong>{entry.displayName}</strong>
                  <small>{entry.devices.length} device(s)</small>
                </span>
              </label>
            ))}
          </div>

          <button type="submit" disabled={isCreatingRoom}>
            {isCreatingRoom ? 'Wrapping room keys...' : 'Create encrypted room'}
          </button>
        </form>

        <section className="directory">
          <div className="directory-head">
            <h2>Known people</h2>
            <span>{directory.length}</span>
          </div>
          <ul className="directory-list">
            {directory.map((entry) => (
              <li key={entry.userId}>
                <div>
                  <strong>{entry.displayName}</strong>
                  <small>{entry.devices.length} device(s)</small>
                </div>
                <span>
                  {entry.devices.length > 0 ? 'ready' : 'offline'}
                </span>
              </li>
            ))}
          </ul>
        </section>
      </aside>

      <main className="thread">
        <header className="thread-head">
          <div>
            <p className="eyebrow">Active room</p>
            <h2>{selectedConversation?.title ?? 'Choose a room'}</h2>
          </div>
          <div className="thread-head-actions">
            <p className="thread-status">
              {isBootstrapping || isConversationLoading
                ? 'Syncing timeline...'
                : statusText}
            </p>
            {selectedConversation ? (
              callState.room ? (
                <button type="button" className="ghost-button" onClick={leaveCall}>
                  Leave call
                </button>
              ) : (
                <button
                  type="button"
                  className="ghost-button"
                  disabled={isJoiningCall || !selectedKey}
                  onClick={handleJoinCall}
                >
                  {isJoiningCall ? 'Joining call...' : 'Join encrypted call'}
                </button>
              )
            ) : null}
          </div>
        </header>

        {callState.status !== 'idle' ? (
          <section className="call-panel">
            <div className="call-panel-head">
              <div>
                <p className="eyebrow">LiveKit E2EE</p>
                <h3>{callState.roomTitle ?? selectedConversation?.title ?? 'Call'}</h3>
              </div>
              <span className="call-badge">{callState.status}</span>
            </div>

            {callState.error ? (
              <p className="call-error">{callState.error}</p>
            ) : null}

            <div className="call-grid">
              {callState.participants.map((participant) => (
                <ParticipantTile
                  key={participant.identity}
                  participant={participant}
                />
              ))}
            </div>
          </section>
        ) : null}

        {selectedConversation ? (
          <>
            <section className="message-stream" aria-live="polite">
              {selectedMessages.length === 0 ? (
                <div className="empty-thread">
                  <p>No messages yet.</p>
                  <span>This room already has its own wrapped secret key.</span>
                </div>
              ) : (
                selectedMessages.map((message) => {
                  const ownMessage = message.authorUserId === session.userId;
                  const rendered = decryptedMessages[message.id];
                  const body = rendered?.body ?? 'Encrypted message';
                  return (
                    <article
                      key={message.id}
                      className={
                        ownMessage ? 'message-bubble own' : 'message-bubble'
                      }
                    >
                      <div className="message-meta">
                        <strong>{message.authorName}</strong>
                        <span>{formatStamp(message.createdAt)}</span>
                      </div>
                      <p>{body}</p>
                      <div className="message-foot">
                        {message.authorDeviceLabel ? (
                          <small>via {message.authorDeviceLabel}</small>
                        ) : (
                          <small>{message.kind}</small>
                        )}
                        {rendered?.error ? (
                          <small>{rendered.error}</small>
                        ) : message.senderKeyGeneration !== null ? (
                          <small>key {message.senderKeyGeneration}</small>
                        ) : null}
                      </div>
                    </article>
                  );
                })
              )}
            </section>

            <form className="composer" onSubmit={handleSendMessage}>
              <label className="sr-only" htmlFor="message-body">
                Message body
              </label>
              <textarea
                id="message-body"
                rows={3}
                value={draftMessage}
                onChange={(event) => setDraftMessage(event.target.value)}
                placeholder={
                  selectedKey
                    ? 'Encrypt the next household update...'
                    : 'Waiting for this browser to unwrap the room key...'
                }
                disabled={!selectedKey}
              />
              <div className="composer-actions">
                <span>
                  {selectedConversation.memberCount} members, key{' '}
                  {selectedDetail?.keyGeneration ?? 0}
                </span>
                <button
                  className="primary-button"
                  type="submit"
                  disabled={isSending || !selectedKey}
                >
                  {isSending ? 'Encrypting...' : 'Send encrypted message'}
                </button>
              </div>
            </form>
          </>
        ) : (
          <section className="empty-thread">
            <p>No room selected.</p>
            <span>Create a room or pick one from the left rail.</span>
          </section>
        )}
      </main>

      <aside className="inspector">
        <section className="inspector-card">
          <p className="eyebrow">Session</p>
          <h2>{session.displayName}</h2>
          <dl>
            <div>
              <dt>Device</dt>
              <dd>{session.deviceLabel}</dd>
            </div>
            <div>
              <dt>Connection</dt>
              <dd>{connectionState}</dd>
            </div>
            <div>
              <dt>Cached rooms</dt>
              <dd>{conversations.length}</dd>
            </div>
            <div>
              <dt>Private key</dt>
              <dd>{deviceKeys[session.deviceId] ? 'Present' : 'Missing'}</dd>
            </div>
          </dl>
          <div className="stacked-actions">
            <button
              type="button"
              className="primary-button"
              disabled={isGeneratingLinkToken}
              onClick={handleGenerateLinkToken}
            >
              {isGeneratingLinkToken ? 'Generating token...' : 'Create link token'}
            </button>
            <button type="button" onClick={resetSession}>
              Reset browser session
            </button>
          </div>
          {linkToken ? (
            <div className="token-card">
              <strong>{linkToken.token}</strong>
              <span>Expires {formatExpiry(linkToken.expiresAt)}</span>
            </div>
          ) : null}
        </section>

        <section className="inspector-card">
          <p className="eyebrow">Current room</p>
          <h2>{selectedDetail?.title ?? 'No room selected'}</h2>
          {selectedDetail ? (
            <>
              <dl>
                <div>
                  <dt>Room name</dt>
                  <dd>{selectedDetail.roomName}</dd>
                </div>
                <div>
                  <dt>Key generation</dt>
                  <dd>{selectedDetail.keyGeneration ?? 0}</dd>
                </div>
                <div>
                  <dt>Key state</dt>
                  <dd>{selectedKey ? 'Unwrapped locally' : 'Waiting on device unwrap'}</dd>
                </div>
              </dl>
              <ul className="member-list">
                {selectedDetail.members.map((member) => (
                  <li key={member.userId}>
                    <strong>{member.displayName}</strong>
                    <span>{member.role}</span>
                  </li>
                ))}
              </ul>
              {addableContacts.length > 0 ? (
                <form className="add-member-form" onSubmit={handleAddMember}>
                  <label>
                    <span>Add member with key rotation</span>
                    <select
                      value={memberToAdd}
                      onChange={(event) => setMemberToAdd(event.target.value)}
                    >
                      <option value="">Choose a person</option>
                      {addableContacts.map((entry) => (
                        <option key={entry.userId} value={entry.userId}>
                          {entry.displayName}
                        </option>
                      ))}
                    </select>
                  </label>
                  <button
                    type="submit"
                    className="ghost-button"
                    disabled={!memberToAdd || isAddingMember}
                  >
                    {isAddingMember ? 'Rotating key...' : 'Add member'}
                  </button>
                </form>
              ) : null}
            </>
          ) : (
            <p className="inspector-copy">
              Member details and key state appear here when a room is active.
            </p>
          )}
        </section>
      </aside>
    </div>
  );
}

export default App;
