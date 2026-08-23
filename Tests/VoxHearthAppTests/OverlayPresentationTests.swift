import Testing
@testable import VoxHearthApp

@Test func overlayPolicyShowsAndPositionsOnlyWhenHidden() {
    #expect(
        OverlayPresentationPolicy.decide(
            isVisible: false,
            currentText: "Listening for speech…",
            incomingText: "hello"
        ) == OverlayPresentationDecision(
            applyText: true,
            present: true,
            reposition: true
        )
    )
}

@Test func overlayPolicyUpdatesChangedVisibleTextWithoutPresentingAgain() {
    #expect(
        OverlayPresentationPolicy.decide(
            isVisible: true,
            currentText: "hello",
            incomingText: "hello world"
        ) == OverlayPresentationDecision(
            applyText: true,
            present: false,
            reposition: false
        )
    )
}

@Test func overlayPolicyDoesNothingForRepeatedVisibleText() {
    #expect(
        OverlayPresentationPolicy.decide(
            isVisible: true,
            currentText: "hello",
            incomingText: "hello"
        ) == OverlayPresentationDecision(
            applyText: false,
            present: false,
            reposition: false
        )
    )
}
