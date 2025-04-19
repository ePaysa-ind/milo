// lib/models/memory.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Memory {
  final String id;
  final String userId;
  final String title;
  final String audioPath;
  final String transcription;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;
  final String? summary;
  final DateTime? updatedAt;
  final int? audioDuration;
  final bool isProcessing;

  // Getter for audioUrl to maintain compatibility
  String get audioUrl => audioPath;

  // Helper method to check if fully processed
  bool get isFullyProcessed =>
      transcription.isNotEmpty &&
          (summary != null && summary!.isNotEmpty);

  Memory({
    required this.id,
    required this.userId,
    required this.title,
    required this.audioPath,
    this.transcription = '', // Default empty string for transcription
    required this.createdAt,
    this.metadata,
    this.summary,
    this.updatedAt,
    this.audioDuration,
    this.isProcessing = false,
  });

  // Create from Firestore document
  factory Memory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Memory(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? 'Untitled Memory',
      audioPath: data['audioPath'] ?? '',
      transcription: data['transcription'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      metadata: data['metadata'],
      summary: data['summary'],
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      audioDuration: data['audioDuration'],
      isProcessing: data['isProcessing'] ?? false,
    );
  }

  // Convert to map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'audioPath': audioPath,
      'transcription': transcription,
      'createdAt': FieldValue.serverTimestamp(),
      'metadata': metadata,
      'summary': summary,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'audioDuration': audioDuration,
      'isProcessing': isProcessing,
    };
  }

  // Create a copy with updated fields
  Memory copyWith({
    String? id,
    String? userId,
    String? title,
    String? audioPath,
    String? transcription,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
    String? summary,
    DateTime? updatedAt,
    int? audioDuration,
    bool? isProcessing,
  }) {
    return Memory(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      audioPath: audioPath ?? this.audioPath,
      transcription: transcription ?? this.transcription,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
      summary: summary ?? this.summary,
      updatedAt: updatedAt ?? this.updatedAt,
      audioDuration: audioDuration ?? this.audioDuration,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}