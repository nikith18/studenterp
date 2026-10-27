enum RequestStatus { pending, approved, rejected }

enum DisputeStatus { pending, underReview, resolved, rejected }

enum SessionStatus { open, closed }

enum RiskLevel { safe, atRisk, critical }

enum NotificationType {
  lowAttendance,
  attendanceCorrected,
  reportReady,
  requestDecision,
  disputeUpdate,
}
