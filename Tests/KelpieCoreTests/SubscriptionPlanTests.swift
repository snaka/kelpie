import Testing
@testable import KelpieCore

@Suite("SubscriptionPlan")
struct SubscriptionPlanTests {

    @Test("The plan pairs every global kind with one status subscription per pane")
    func perPaneStatus() {
        let plan = SubscriptionPlan.subscriptions(paneIDs: ["w1:p1", "w0:p2"])
        for type in SubscriptionPlan.globalTypes {
            #expect(plan.contains(SubscriptionRequest(type: type, paneID: nil)))
        }
        let perPane = plan.filter { $0.type == SubscriptionPlan.agentStatusType }
        #expect(perPane.map(\.paneID) == ["w0:p2", "w1:p1"])
    }

    @Test("The pane order is deterministic regardless of input order")
    func deterministicOrder() {
        let a = SubscriptionPlan.subscriptions(paneIDs: ["w1:p1", "w0:p2"])
        let b = SubscriptionPlan.subscriptions(paneIDs: ["w0:p2", "w1:p1"])
        #expect(a == b)
    }

    @Test("Duplicate pane ids collapse to one subscription")
    func duplicatesCollapse() {
        let plan = SubscriptionPlan.subscriptions(paneIDs: ["w0:p1", "w0:p1"])
        let perPane = plan.filter { $0.type == SubscriptionPlan.agentStatusType }
        #expect(perPane.count == 1)
    }

    @Test("No panes still subscribes the global kinds")
    func emptyPanes() {
        let plan = SubscriptionPlan.subscriptions(paneIDs: [])
        #expect(plan == SubscriptionPlan.globalTypes.map { SubscriptionRequest(type: $0, paneID: nil) })
    }

    @Test("A changed pane set requires a rebuild; an equal one does not")
    func needsRebuild() {
        #expect(SubscriptionPlan.needsRebuild(subscribed: ["w0:p1"], current: ["w0:p1", "w0:p2"]))
        #expect(SubscriptionPlan.needsRebuild(subscribed: ["w0:p1"], current: []))
        #expect(!SubscriptionPlan.needsRebuild(subscribed: ["w0:p1"], current: ["w0:p1"]))
    }
}
