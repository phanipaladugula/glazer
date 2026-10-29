import LocalAuthentication

/// Confirms that the Mac's owner is present, with Touch ID or the login password.
///
/// Glazer asks before setting up or deleting face lock, so nobody else at the Mac can
/// replace the enrolled face with their own.
public enum OwnerAuthentication {
    /// Asks the user to authenticate. Returns `false` if they cancel or fail.
    ///
    /// - Parameter reason: Completes the system's sentence "Glazer is trying to …".
    @MainActor
    public static func confirm(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No password is set and no Touch ID: nothing to ask for.
            return true
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
