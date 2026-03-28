import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../models.dart';
import 'crypto_service.dart';

class CallParticipantView {
  const CallParticipantView({
    required this.identity,
    required this.displayName,
    required this.isLocal,
    required this.videoTrack,
    required this.audioTrack,
  });

  final String identity;
  final String displayName;
  final bool isLocal;
  final VideoTrack? videoTrack;
  final AudioTrack? audioTrack;
}

class CallLaunch {
  const CallLaunch({
    required this.room,
    required this.roomTitle,
  });

  final Room room;
  final String roomTitle;
}

abstract class LiveKitService {
  Future<Room> connectEncryptedRoom(
    CallJoinPayload joinPayload,
    String conversationKeyMaterial,
  );

  List<CallParticipantView> snapshotParticipants(Room room);
}

class DefaultLiveKitService implements LiveKitService {
  DefaultLiveKitService({required CryptoService cryptoService})
      : _cryptoService = cryptoService;

  final CryptoService _cryptoService;

  @override
  Future<Room> connectEncryptedRoom(
    CallJoinPayload joinPayload,
    String conversationKeyMaterial,
  ) async {
    final keyProvider = await BaseKeyProvider.create(sharedKey: true);
    final rawKey = await _cryptoService.deriveLiveKitKey(
      conversationKeyMaterial,
      joinPayload.roomName,
    );
    await keyProvider.setRawKey(Uint8List.fromList(rawKey));

    final room = Room();
    await room.connect(
      joinPayload.serverUrl,
      joinPayload.token,
      roomOptions: RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        encryption: E2EEOptions(keyProvider: keyProvider),
      ),
    );
    final localParticipant = room.localParticipant;
    if (localParticipant != null) {
      await localParticipant.setMicrophoneEnabled(true);
      try {
        await localParticipant.setCameraEnabled(true);
      } catch (_) {
        // Some Android emulators expose no camera device.
      }
    }

    return room;
  }

  @override
  List<CallParticipantView> snapshotParticipants(Room room) {
    final participants = <CallParticipantView>[];
    final localParticipant = room.localParticipant;
    if (localParticipant != null) {
      participants.add(
        _participantView(localParticipant, isLocal: true),
      );
    }

    participants.addAll(
      room.remoteParticipants.values.map(
        (participant) => _participantView(participant, isLocal: false),
      ),
    );

    return participants
        .where(
          (participant) =>
              participant.isLocal ||
              participant.videoTrack != null ||
              participant.audioTrack != null,
        )
        .toList(growable: false);
  }

  CallParticipantView _participantView(
    Participant participant, {
    required bool isLocal,
  }) {
    return CallParticipantView(
      identity: participant.identity,
      displayName:
          participant.name.isEmpty ? participant.identity : participant.name,
      isLocal: isLocal,
      videoTrack: _firstVideoTrack(participant),
      audioTrack: _firstAudioTrack(participant),
    );
  }

  AudioTrack? _firstAudioTrack(Participant participant) {
    for (final publication in participant.trackPublications.values) {
      final track = publication.track;
      if (track is AudioTrack) {
        return track;
      }
    }

    return null;
  }

  VideoTrack? _firstVideoTrack(Participant participant) {
    for (final publication in participant.trackPublications.values) {
      final track = publication.track;
      if (track is VideoTrack) {
        return track;
      }
    }

    return null;
  }
}

final liveKitServiceProvider = Provider<LiveKitService>((ref) {
  final cryptoService = ref.watch(cryptoServiceProvider);
  return DefaultLiveKitService(cryptoService: cryptoService);
});

class CallRoomPage extends StatefulWidget {
  const CallRoomPage({
    super.key,
    required this.room,
    required this.roomTitle,
    required this.liveKitService,
  });

  final Room room;
  final String roomTitle;
  final LiveKitService liveKitService;

  @override
  State<CallRoomPage> createState() => _CallRoomPageState();
}

class _CallRoomPageState extends State<CallRoomPage> {
  @override
  void initState() {
    super.initState();
    widget.room.addListener(_sync);
  }

  @override
  void dispose() {
    widget.room.removeListener(_sync);
    unawaited(widget.room.disconnect());
    super.dispose();
  }

  void _sync() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.liveKitService.snapshotParticipants(widget.room);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomTitle),
        actions: [
          TextButton(
            key: const Key('call-leave'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Leave'),
          ),
        ],
      ),
      body: participants.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 1,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: participants.length,
              itemBuilder: (context, index) {
                final participant = participants[index];
                final initials = participant.displayName
                    .split(RegExp(r'\s+'))
                    .where((part) => part.isNotEmpty)
                    .take(2)
                    .map((part) => part.characters.first.toUpperCase())
                    .join();

                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (participant.videoTrack != null)
                        VideoTrackRenderer(participant.videoTrack!)
                      else
                        ColoredBox(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          child: Center(
                            child: CircleAvatar(
                              radius: 42,
                              child: Text(initials.isEmpty ? 'FC' : initials),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    participant.displayName,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                if (participant.isLocal)
                                  const Text(
                                    'You',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
