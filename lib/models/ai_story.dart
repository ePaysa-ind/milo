// lib/models/ai_story.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class AiStory {
  final String id;
  final String memoryId; // ID of the original memory
  final String userId; // Added userId field
  final String title;
  final String content; // The generated story
  final String sentiment; // Detected sentiment: positive, negative, neutral, etc.
  final DateTime createdAt;
  final Map<String, dynamic>? metadata; // Additional data like themes, keywords, etc.

  AiStory({
    required this.id,
    required this.memoryId,
    required this.userId, // Added required userId parameter
    required this.title,
    required this.content,
    required this.sentiment,
    required this.createdAt,
    this.metadata,
  });

  // Create from Firestore document
  factory AiStory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AiStory(
      id: doc.id,
      memoryId: data['memoryId'] ?? '',
      userId: data['userId'] ?? '', // Added userId field
      title: data['title'] ?? 'Untitled Story',
      content: data['content'] ?? '',
      sentiment: data['sentiment'] ?? 'neutral',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      metadata: data['metadata'],
    );
  }

  // Convert to map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'memoryId': memoryId,
      'userId': userId, // Added userId field to map
      'title': title,
      'content': content,
      'sentiment': sentiment,
      'createdAt': FieldValue.serverTimestamp(),
      'metadata': metadata,
    };
  }

  // Create a copy with updated fields
  AiStory copyWith({
    String? id,
    String? memoryId,
    String? userId, // Added userId parameter
    String? title,
    String? content,
    String? sentiment,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) {
    return AiStory(
      id: id ?? this.id,
      memoryId: memoryId ?? this.memoryId,
      userId: userId ?? this.userId, // Added userId field
      title: title ?? this.title,
      content: content ?? this.content,
      sentiment: sentiment ?? this.sentiment,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }
}