import {
  ExternalE2EEKeyProvider,
  Room,
  Track,
  type Participant,
  type TrackPublication,
} from 'livekit-client';

import { deriveLiveKitKey } from './crypto';
import type { CallJoinPayload } from './types';

export interface CallParticipantView {
  identity: string;
  displayName: string;
  isLocal: boolean;
  videoTrack: Track | null;
  audioTrack: Track | null;
}

function firstTrack(
  participant: Participant,
  kind: Track.Kind,
): Track | null {
  const publications = Array.from(
    participant.trackPublications.values(),
  ) as TrackPublication[];
  const publication = publications.find(
    (item) => item.kind === kind && item.track,
  );

  return publication?.track ?? null;
}

export function snapshotCallParticipants(room: Room) {
  const participants = [room.localParticipant, ...room.remoteParticipants.values()];

  return participants
    .map((participant) => ({
      identity: participant.identity,
      displayName: participant.name || participant.identity,
      isLocal: participant.isLocal,
      videoTrack: firstTrack(participant, Track.Kind.Video),
      audioTrack: firstTrack(participant, Track.Kind.Audio),
    }))
    .filter(
      (participant) =>
        participant.isLocal || participant.videoTrack || participant.audioTrack,
    ) as CallParticipantView[];
}

export async function connectEncryptedRoom(
  joinPayload: CallJoinPayload,
  conversationKeyMaterial: string,
) {
  const keyProvider = new ExternalE2EEKeyProvider();
  const sharedKey = await deriveLiveKitKey(
    conversationKeyMaterial,
    joinPayload.roomName,
  );

  await keyProvider.setKey(sharedKey);

  const room = new Room({
    adaptiveStream: true,
    dynacast: true,
    encryption: {
      keyProvider,
      worker: new Worker(new URL('livekit-client/e2ee-worker', import.meta.url)),
    },
  });

  await room.connect(joinPayload.serverUrl, joinPayload.token);
  await room.setE2EEEnabled(true);
  await room.startAudio();
  await room.localParticipant.setMicrophoneEnabled(true);
  await room.localParticipant.setCameraEnabled(true);

  return room;
}
