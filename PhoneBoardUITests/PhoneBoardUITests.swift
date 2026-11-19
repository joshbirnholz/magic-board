import XCTest

final class PhoneBoardUITests: XCTestCase {
    @MainActor func testTappedPermanentAndTravellingMiniCard() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-permanent-hand"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        // The arriving creature occupies the rightmost slot, behind the expanded stack.
        app.buttons["phone-stack"].tap()
        expandPhoneHand(app)
        app.descendants(matching: .any).matching(identifier: "phone-hand-4").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        let actions = app.tables["phone-hand-actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.cells.containing(.staticText, identifier: "Play Tapped").firstMatch.tap()
        let fish = app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Dandân'"))
        XCTAssertTrue(fish.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(fish.firstMatch.value as? String, "Tapped")
        let dark = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        dark.name = "Permanent enters tapped — dark mini-card"; dark.lifetime = .keepAlways; add(dark)
        fish.firstMatch.tap()
        XCTAssertEqual(fish.firstMatch.value as? String, "Untapped")
        let light = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        light.name = "Same permanent untapped — light mini-card"; light.lifetime = .keepAlways; add(light)
        expandPhoneHand(app)
        app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35))
            // Out above the open hand (which collapses once the card leaves it) onto open battlefield.
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45)), withVelocity: 250, thenHoldForDuration: 0.1)
        // A newly inserted mini can expose the generic permanent identifier until its
        // stat-visibility relay is reflected by layout. Count either battlefield form.
        let bears = app.buttons.matching(NSPredicate(format: "label == 'Grizzly Bears' AND (identifier == 'phone-creature-card' OR identifier == 'phone-permanent-card')"))
        expectation(for: NSPredicate(format: "count == 3"), evaluatedWith: bears)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch.isHittable)
        let landed = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landed.name = "Hand card morphed into battlefield mini-card"; landed.lifetime = .keepAlways; add(landed)
    }

    /// Targets are chosen only by dragging from a stack card: no targeting mode or bar. Dragging
    /// onto a card toggles it as a target; dragging onto a pile moves the card there unresolved.
    @MainActor func testStackCardDragsTargetAndMovesToZones() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-targets"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let stack = app.buttons["phone-stack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 15))
        let before = Int(stack.label.components(separatedBy: " ").last ?? "") ?? 0
        expandPhoneHand(app)
        app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        app.tables["phone-hand-actions"].cells.containing(.staticText, identifier: "Play").firstMatch.tap()
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        XCTAssertEqual(stack.label, "Stack · \(before + 1)")
        XCTAssertFalse(app.buttons["phone-target-done"].exists, "Casting has no targeting bar")
        XCTAssertEqual(stack.value as? String, "0 target connections")

        let top = app.buttons.matching(identifier: "phone-stack-full-card")
            .matching(NSPredicate(format: "value BEGINSWITH 'Top of stack'")).firstMatch
        let enemyBear = app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Grizzly Bears'"))
            .allElementsBoundByIndex.min { $0.frame.midY < $1.frame.midY }!
        top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: enemyBear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.3)
        expectation(for: NSPredicate(format: "value == '1 target connections'"), evaluatedWith: stack)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(enemyBear.value as? String, "Untapped", "Targeting must not tap the creature")
        let arc = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        arc.name = "Stack drag — targeted creature"; arc.lifetime = .keepAlways; add(arc)
        // Arcs stay drawn, from the cards' visible edges, while the stack is collapsed.
        stack.tap()
        expectation(for: NSPredicate(format: "value == '1 target connections'"), evaluatedWith: stack)
        waitForExpectations(timeout: 5)
        let collapsedArc = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        collapsedArc.name = "Collapsed stack still shows its target arc"; collapsedArc.lifetime = .keepAlways; add(collapsedArc)
        stack.tap()
        // The same drag again removes the target.
        top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: enemyBear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.3)
        expectation(for: NSPredicate(format: "value == '0 target connections'"), evaluatedWith: stack)
        waitForExpectations(timeout: 5)
        // Your own life total is a target too (it sits in the band over the hand).
        let ownLife = app.descendants(matching: .any).matching(identifier: "phone-life-local").firstMatch
        top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: ownLife.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.3)
        expectation(for: NSPredicate(format: "value == '1 target connections'"), evaluatedWith: stack)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(stack.label, "Stack · \(before + 1)", "Targeting yourself must not move the spell to your hand")
        // Onto your graveyard: off the stack without resolving.
        let graveyard = app.buttons["phone-graveyard-a"]
        let graves = Int(graveyard.value as? String ?? "0") ?? 0
        top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: graveyard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.3)
        expectation(for: NSPredicate(format: "value == '\(graves + 1)'"), evaluatedWith: graveyard)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(stack.label, "Stack · \(before)")
    }

    /// An instant held over a permanent offers to cast it targeting that permanent.
    @MainActor func testHandSpellDraggedOntoCreatureCastsTargetingIt() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-targets"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let stack = app.buttons["phone-stack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 15))
        let before = Int(stack.label.components(separatedBy: " ").last ?? "") ?? 0
        expandPhoneHand(app)
        let enemyBear = app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Grizzly Bears'"))
            .allElementsBoundByIndex.min { $0.frame.midY < $1.frame.midY }!
        app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.3, thenDragTo: enemyBear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.8)
        expectation(for: NSPredicate(format: "label == 'Stack · \(before + 1)'"), evaluatedWith: stack)
        waitForExpectations(timeout: 5)
        expectation(for: NSPredicate(format: "value == '1 target connections'"), evaluatedWith: stack)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["phone-target-done"].exists)
    }

    @MainActor func testArenaStackFansCollapsesAndResolves() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-stack"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let stack = app.buttons["phone-stack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 15))
        XCTAssertEqual(stack.label, "Stack · 4")
        let cards = app.buttons.matching(identifier: "phone-stack-full-card")
        XCTAssertEqual(cards.count, 4)
        let top = cards.matching(NSPredicate(format: "value BEGINSWITH 'Top of stack'")).firstMatch
        XCTAssertEqual(top.label, "Vision Charm")
        XCTAssertGreaterThan(top.frame.width, 95)
        XCTAssertLessThan(top.frame.maxX, app.frame.maxX)
        let oldest = cards.matching(NSPredicate(format: "label == 'Memory Lapse'")).firstMatch
        XCTAssertLessThan(oldest.frame.minX, top.frame.minX, "Older spells should fan to the left")
        let fan = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fan.name = "Arena stack — four spells"; fan.lifetime = .keepAlways; add(fan)
        // One chevron-and-count control collapses and expands the stack; there is no list.
        stack.tap()
        XCTAssertFalse(app.navigationBars["Stack"].exists)
        XCTAssertFalse(app.buttons["phone-stack-collapse"].exists)
        XCTAssertFalse(app.buttons["phone-stack-resolve"].exists)
        XCTAssertEqual(cards.count, 0)
        XCTAssertTrue(app.buttons["phone-stack-peek"].exists)
        XCTAssertEqual(stack.label, "Stack · 4", "Hiding must not resolve anything")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch.isHittable)
        let hidden = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        hidden.name = "Arena stack — collapsed"; hidden.lifetime = .keepAlways; add(hidden)
        app.buttons["phone-stack-peek"].tap()
        XCTAssertEqual(cards.count, 4)
        for _ in 0..<3 { app.buttons["phone-stack-resolve"].tap() }
        XCTAssertEqual(stack.label, "Stack · 1")
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.firstMatch.label, "Memory Lapse")
        let single = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        single.name = "Arena stack — single spell"; single.lifetime = .keepAlways; add(single)
        app.buttons["phone-stack-resolve"].tap()
        XCTAssertFalse(stack.exists)
        XCTAssertFalse(app.buttons["phone-stack-resolve"].exists)
    }

    @MainActor func testResolutionFliesPermanentAndSpellToTheirZones() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-resolution"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let stack = app.buttons["phone-stack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 15))
        XCTAssertEqual(stack.label, "Stack · 2")
        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        before.name = "Resolution — permanent ready on stack"; before.lifetime = .keepAlways; add(before)
        app.buttons["phone-stack-resolve"].tap()
        XCTAssertEqual(stack.label, "Stack · 1")
        XCTAssertEqual(app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Grizzly Bears'")).count, 2)
        let permanent = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        permanent.name = "Resolution — creature landed"; permanent.lifetime = .keepAlways; add(permanent)
        app.buttons["phone-stack-resolve"].tap()
        XCTAssertFalse(stack.exists)
        XCTAssertEqual(app.buttons["phone-graveyard-b"].value as? String, "1")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "phone-resolution-preview").firstMatch.exists)
        let spell = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        spell.name = "Resolution — spell in graveyard"; spell.lifetime = .keepAlways; add(spell)
    }

    /// Discards through the hand card's menu (the open hand covers the HUD piles on small phones,
    /// so a straight drag from it onto the graveyard isn't a drop there).
    @MainActor private func discardFirstHandCard(_ app: XCUIApplication) {
        expandPhoneHand(app)
        app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        let actions = app.tables["phone-hand-actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.cells.containing(.staticText, identifier: "Discard").firstMatch.tap()
    }

    @MainActor private func browserCards(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "phone-browser-card")
    }

    /// Hand cards can only be picked up from the expanded hand.
    @MainActor private func expandPhoneHand(_ app: XCUIApplication) {
        let hand = app.descendants(matching: .any).matching(identifier: "phone-local-hand").firstMatch
        guard hand.value as? String != "Expanded" else { return }
        app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        expectation(for: NSPredicate(format: "value == 'Expanded'"), evaluatedWith: hand)
        waitForExpectations(timeout: 5)
    }

    @MainActor func testOriginalBoardPhoneHandAndStack() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let stack = app.buttons["phone-stack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 15))
        let lands = app.descendants(matching: .any).matching(identifier: "phone-opponent-lands").firstMatch
        XCTAssertTrue(lands.exists)
        XCTAssertTrue(lands.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Island, 5'")).firstMatch.exists)
        let creature = app.buttons.matching(identifier: "phone-creature-card").firstMatch
        XCTAssertTrue(creature.exists)
        XCTAssertGreaterThanOrEqual(creature.frame.width, 48)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Original board adapted to phone"
        shot.lifetime = .keepAlways
        add(shot)
        let handCard = app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch
        XCTAssertTrue(handCard.exists)
        expandPhoneHand(app)
        let start = handCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.8, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        XCTAssertTrue(stack.label.contains("2"))
        app.buttons["phone-stack-resolve"].tap()
        XCTAssertTrue(stack.label.contains("1"))
        let bearer = app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Grizzly Bears'")).firstMatch
        bearer.press(forDuration: 0.7)
        let pages = app.descendants(matching: .any).matching(identifier: "phone-inspector-pages").firstMatch
        XCTAssertTrue(pages.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Attached Cards…"].exists)
        pages.swipeLeft()
        XCTAssertTrue(app.buttons["Unattach"].waitForExistence(timeout: 5))
    }
    @MainActor func testCrowdedOriginalBoardKeepsReadableCardsAndCanBrowse() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-crowded"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        let creature = app.buttons.matching(identifier: "phone-creature-card").firstMatch
        XCTAssertGreaterThanOrEqual(creature.frame.width, 48)
        let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Next battlefield cards'")).firstMatch
        XCTAssertTrue(next.exists)
        let value = next.value as? String
        next.tap()
        let updated = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Next battlefield cards'")).firstMatch
        XCTAssertNotEqual(updated.value as? String, value)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Original board — crowded readable layout"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testExistingCompanionCanSelectPlayerAndReturnToBoard() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-companion-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Player 2"].waitForExistence(timeout: 15))
        app.buttons["Player 2"].tap()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Memory Lapse'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.navigationBars.buttons["Players"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Battlefield"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Battlefield"].tap()
        XCTAssertTrue(app.staticTexts["Library"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testLandTapsAndRapidLifeChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let lands = app.descendants(matching: .any).matching(identifier: "phone-local-lands").firstMatch
        let island = lands.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Island, 5'")).firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 15))
        island.tap()
        let tapped = lands.descendants(matching: .any).matching(NSPredicate(format: "label == 'Island, 1, tapped'")).firstMatch
        XCTAssertTrue(tapped.waitForExistence(timeout: 5))
        let creature = app.buttons.matching(identifier: "phone-creature-card")
            .matching(NSPredicate(format: "label BEGINSWITH 'Grizzly Bears'"))
            .allElementsBoundByIndex.max { $0.frame.midY < $1.frame.midY }!
        creature.tap()
        XCTAssertEqual(creature.value as? String, "Tapped")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Tapped land and permanent"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        tapped.tap()
        XCTAssertTrue(island.waitForExistence(timeout: 5))
        let increase = app.buttons.matching(identifier: "Increase life").allElementsBoundByIndex.max { $0.frame.midY < $1.frame.midY }!
        for _ in 0..<5 { increase.tap() }
        XCTAssertTrue(app.staticTexts["25"].waitForExistence(timeout: 5))
        let decrease = app.buttons.matching(identifier: "Decrease life").allElementsBoundByIndex.max { $0.frame.midY < $1.frame.midY }!
        for _ in 0..<5 { decrease.tap() }
        XCTAssertTrue(app.staticTexts["20"].exists)
    }

    /// Lands and stack cards are SwiftUI, so the menu zoom uses a UIKit stand-in in the card's
    /// place; the real card must reappear (and stay usable) once the menu is gone.
    @MainActor func testMenusZoomFromLandsAndStackAndRestoreTheCard() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-stack"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        func shot(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        let lands = app.descendants(matching: .any).matching(identifier: "phone-local-lands").firstMatch
        let island = lands.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Island'")).firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 5))
        island.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Switch Control"].waitForExistence(timeout: 5))
        shot("Land menu open")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Switch Control"].waitForNonExistence(timeout: 5))
        sleep(1)
        shot("Land restored after menu")
        XCTAssertTrue(island.isHittable)

        let top = app.buttons.matching(identifier: "phone-stack-full-card")
            .matching(NSPredicate(format: "value BEGINSWITH 'Top of stack'")).firstMatch
        top.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        shot("Stack menu open")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        shot("Stack card restored after menu")
        XCTAssertEqual(app.buttons.matching(identifier: "phone-stack-full-card").count, 4)
        XCTAssertTrue(top.isHittable)

        expandPhoneHand(app)
        shot("Expanded hand corners")
    }

    /// The top card of your library drags off the pile like a hand card: into the hand draws it.
    @MainActor func testTopCardDragsOffLibraryIntoHandAndGraveyardOntoBattlefield() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        let library = app.buttons["phone-library-a"]
        let graveyard = app.buttons["phone-graveyard-a"]
        let libraryCount = Int(library.value as? String ?? "0") ?? 0
        let handCount = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'")).count
        library.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)), withVelocity: 300, thenHoldForDuration: 0.2)
        expectation(for: NSPredicate(format: "value == '\(libraryCount - 1)'"), evaluatedWith: library)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'")).count, handCount + 1)
        // Discard a card, then drag it off the graveyard back onto the battlefield.
        discardFirstHandCard(app)
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: graveyard)
        waitForExpectations(timeout: 5)
        graveyard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.62)), withVelocity: 300, thenHoldForDuration: 0.2)
        expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: graveyard)
        waitForExpectations(timeout: 5)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Graveyard top card dragged onto the battlefield"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Sagas draw their full card image, sit in the right-hand lane, and stay face up when tapped.
    @MainActor func testSagaShowsCardImageAndStaysFaceUpWhenTapped() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-saga"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        app.buttons["phone-stack"].tap() // uncover the right side
        let saga = app.buttons.matching(NSPredicate(format: "label == 'Test Saga'")).firstMatch
        XCTAssertTrue(saga.waitForExistence(timeout: 5))
        sleep(1)
        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        before.name = "Saga untapped"; before.lifetime = .keepAlways; add(before)
        saga.tap()
        expectation(for: NSPredicate(format: "value == 'Tapped'"), evaluatedWith: saga)
        waitForExpectations(timeout: 5)
        sleep(1)
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "Saga tapped"; after.lifetime = .keepAlways; add(after)
    }

    /// A prepare card's menu has a Prepared marker; while prepared, it casts its spell as a copy.
    @MainActor func testPreparedMarkerCastsThePreparedSpell() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-prepare"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let stack = app.buttons["phone-stack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 15))
        let before = Int(stack.label.components(separatedBy: " ").last ?? "") ?? 0
        stack.tap() // uncover the right side of the field
        let scholar = app.buttons.matching(NSPredicate(format: "label == 'Test Scholar'")).firstMatch
        XCTAssertTrue(scholar.waitForExistence(timeout: 5))
        scholar.press(forDuration: 0.8)
        let prepared = app.buttons["card-prepared"]
        XCTAssertTrue(prepared.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Cast Lesson"].exists, "Nothing to cast until prepared")
        prepared.tap()
        // Cast sits directly under the Prepared checkmark once it's checked.
        let castBelow = app.buttons["Cast Lesson"]
        XCTAssertTrue(castBelow.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(castBelow.frame.minY, prepared.frame.maxY - 1)
        let menu = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        menu.name = "Prepared marker checked"; menu.lifetime = .keepAlways; add(menu)
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        let marked = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        marked.name = "Prepared marker on the mini card"; marked.lifetime = .keepAlways; add(marked)
        scholar.press(forDuration: 0.8)
        let cast = app.buttons["Cast Lesson"]
        XCTAssertTrue(cast.waitForExistence(timeout: 5))
        cast.tap()
        expectation(for: NSPredicate(format: "label == 'Stack · \(before + 1)'"), evaluatedWith: stack)
        waitForExpectations(timeout: 5)
    }

    /// A flashback card in the graveyard shows beside the hand (glowing) and can be cast from there.
    @MainActor func testFlashbackCardShowsBesideHandAndCasts() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-flashback"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let stack = app.buttons["phone-stack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 15))
        let before = Int(stack.label.components(separatedBy: " ").last ?? "") ?? 0
        let castable = app.descendants(matching: .any).matching(identifier: "phone-castable-0").firstMatch
        XCTAssertTrue(castable.waitForExistence(timeout: 5))
        XCTAssertEqual(castable.label, "Think Twice")
        let lastHand = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'")).allElementsBoundByIndex
            .map(\.frame.midX).max() ?? 0
        XCTAssertGreaterThan(castable.frame.midX, lastHand, "Castable cards sit to the right of the hand")
        expandPhoneHand(app)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Flashback card beside the hand"; shot.lifetime = .keepAlways; add(shot)
        castable.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        let actions = app.tables["phone-hand-actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.cells.containing(.staticText, identifier: "Play").firstMatch.tap()
        expectation(for: NSPredicate(format: "label == 'Stack · \(before + 1)'"), evaluatedWith: stack)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(castable.exists, "Cast from the graveyard, it leaves the castable cards")
    }

    /// Holding a graveyard card in its pile sheet can mark it castable; it then shows beside the hand.
    /// Piles open in the card browser; its "⋯" menu leads to the list sheet, search and look at.
    @MainActor private func openPileMenuItem(_ app: XCUIApplication, pile: XCUIElement, _ item: String) {
        pile.tap()
        let more = app.buttons["phone-browser-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Tapping a pile opens its browser")
        more.tap()
        let entry = app.buttons[item].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
    }

    /// A library's top card kept revealed to this player shows face up in its browser.
    @MainActor func testRevealedTopCardIsFaceUpInLibraryBrowser() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        let library = app.buttons["phone-library-a"]
        let count = Int(library.value as? String ?? "0") ?? 0
        openPileMenuItem(app, pile: library, "Keep Top Card Revealed To")
        app.buttons["Me"].firstMatch.tap()
        let faceDown = browserCards(app).matching(NSPredicate(format: "label == 'Face-down card'"))
        expectation(for: NSPredicate(format: "count == \(count - 1)"), evaluatedWith: faceDown)
        waitForExpectations(timeout: 5)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Library browser with revealed top"; shot.lifetime = .keepAlways; add(shot)
    }

    /// The card menu's arrows button shows a card's other side only on this phone: the card on the
    /// battlefield keeps its face. Transform, Kamigawa flip and upside-down-back cards.
    @MainActor func testCardMenuPreviewsOtherSide() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-faces"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        let handShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); handShot.name = "Hand ability tile (Cycling)"; handShot.lifetime = .keepAlways; add(handShot)
        app.buttons["phone-stack"].tap() // uncover the right side of the field
        let stackCollapsed = NSPredicate(format: "exists == false")
        expectation(for: stackCollapsed, evaluatedWith: app.buttons["phone-stack-resolve"])
        waitForExpectations(timeout: 5)
        for name in ["Test Werewolf", "Test Flipper", "Test Laboratory"] {
            XCTAssertFalse(app.buttons["phone-stack-resolve"].exists, "The stack stays collapsed (\(name))")
            let card = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5), name)
            // Its left part: the rightmost card's edge can sit under the collapsed stack's peek strip.
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 0.8)
            let other = app.buttons["card-other-side"]
            XCTAssertTrue(other.waitForExistence(timeout: 5), name)
            other.tap()
            sleep(1)
            XCTAssertEqual(other.label, "Show Current Side")
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Other side: \(name)"; shot.lifetime = .keepAlways; add(shot)
            app.buttons["Done"].firstMatch.tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch.waitForExistence(timeout: 5),
                          "The card on the battlefield keeps its face")
        }
    }

    /// A hand card dragged onto an open browser goes into that zone at the spot it's dropped; one
    /// dropped on the browser's dimmed area goes back to the hand instead of behind the browser.
    @MainActor func testHandCardDragsIntoOpenBrowser() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        let graveyard = app.buttons["phone-graveyard-a"]
        discardFirstHandCard(app)
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: graveyard)
        waitForExpectations(timeout: 5)
        graveyard.tap()
        let browser = app.descendants(matching: .any).matching(identifier: "phone-zone-browser").firstMatch
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        let fanCard = browserCards(app).firstMatch
        let handCount = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'")).count
        expandPhoneHand(app)
        app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35))
            .press(forDuration: 0.1, thenDragTo: fanCard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)),
                   withVelocity: 250, thenHoldForDuration: 0.4)
        expectation(for: NSPredicate(format: "value == '2'"), evaluatedWith: graveyard)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(browser.exists, "The browser stays open")
        expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: browserCards(app))
        waitForExpectations(timeout: 5)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Hand card dropped into the graveyard browser"; shot.lifetime = .keepAlways; add(shot)
        // Dropped on the dimmed board area of the browser: back to the hand, not played behind it.
        let battlefieldBefore = app.buttons.matching(NSPredicate(format: "identifier == 'phone-creature-card' OR identifier == 'phone-permanent-card'")).count
        expandPhoneHand(app)
        app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35))
            // Between the browser's title and its Battlefield zone, above the fan.
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.21)),
                   withVelocity: 250, thenHoldForDuration: 0.2)
        sleep(1)
        XCTAssertEqual(graveyard.value as? String, "2")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier == 'phone-creature-card' OR identifier == 'phone-permanent-card'")).count, battlefieldBefore)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'")).count, handCount - 1)
    }

    /// Debug aid: records the reserved regions (run on an iPhone Duo).
    @MainActor func testLogReservedRegions() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-log-regions"]
        app.launch() // the board is landscape-only; no orientation change needed
        let regions = app.descendants(matching: .any).matching(identifier: "phone-regions").firstMatch
        XCTAssertTrue(regions.waitForExistence(timeout: 15))
        sleep(2)
        let note = XCTAttachment(string: regions.label); note.name = "Reserved regions"; note.lifetime = .keepAlways; add(note)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Regions board"; shot.lifetime = .keepAlways; add(shot)
    }

    /// One creature and two planeswalkers: both walkers show at once, with no row paging.
    @MainActor func testTwoPlaneswalkersShowWithoutPaging() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-walkers"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        app.buttons["phone-stack"].tap() // uncover the right side of the field
        sleep(1)
        for name in ["Test Walker One", "Test Walker Two", "Grizzly Bears"] {
            let card = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5), name)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(card.frame), "\(name) is on screen")
        }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Next battlefield cards'")).firstMatch.exists, "No row pages")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Two planeswalkers and a creature"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Arena's back row: noncreature permanents sit in the land rows, right of the lands, at land size.
    @MainActor func testNoncreaturePermanentsSitInTheBackRow() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-backrow"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        app.buttons["phone-stack"].tap() // uncover the right side of the field
        sleep(1)
        let creatures = app.buttons.matching(identifier: "phone-creature-card").allElementsBoundByIndex
        let creatureHeight = creatures.map(\.frame.height).max() ?? 0
        let midY = app.windows.firstMatch.frame.midY
        for name in ["Test Mox", "Test Clamp", "Test Anthem"] {
            let copies = app.buttons.matching(NSPredicate(format: "label == %@", name)).allElementsBoundByIndex
            XCTAssertEqual(copies.count, 2, "\(name) on both sides")
            for card in copies {
                XCTAssertTrue(app.windows.firstMatch.frame.contains(card.frame), "\(name) on screen")
                XCTAssertLessThan(card.frame.height, creatureHeight, "\(name) at land size")
                // Own back row below the creatures, the opponent's above.
                let own = card.frame.midY > midY
                let ownCreatures = creatures.filter { ($0.frame.midY > midY) == own }
                if own { XCTAssertTrue(ownCreatures.allSatisfy { card.frame.midY > $0.frame.midY }, "\(name) behind its creatures") }
                else { XCTAssertTrue(ownCreatures.allSatisfy { card.frame.midY < $0.frame.midY }, "\(name) behind its creatures") }
            }
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Back row"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testTappingGraveyardOpensItsBrowser() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        let graveyard = app.buttons["phone-graveyard-a"]
        discardFirstHandCard(app)
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: graveyard)
        waitForExpectations(timeout: 5)
        graveyard.tap()
        let browser = app.descendants(matching: .any).matching(identifier: "phone-zone-browser").firstMatch
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        XCTAssertEqual(browserCards(app).count, 1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Graveyard browser"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["phone-browser-done"].firstMatch.tap()
        XCTAssertFalse(browser.waitForExistence(timeout: 2))
    }

    @MainActor func testGraveyardCardMarkedCastableShowsBesideHand() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        let graveyard = app.buttons["phone-graveyard-a"]
        discardFirstHandCard(app)
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: graveyard)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "phone-castable-0").firstMatch.exists)
        openPileMenuItem(app, pile: graveyard, "Open List")
        let cell = app.tables.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.press(forDuration: 1.0)
        let castable = app.buttons["Castable"]
        XCTAssertTrue(castable.waitForExistence(timeout: 5))
        castable.tap()
        let close = app.buttons["phone-sheet-close"].firstMatch
        if close.waitForExistence(timeout: 2) { close.tap() } else { app.buttons["Done"].firstMatch.tap() }
        let beside = app.descendants(matching: .any).matching(identifier: "phone-castable-0").firstMatch
        XCTAssertTrue(beside.waitForExistence(timeout: 5), "A card marked castable shows beside the hand")
    }

    /// A castable graveyard card dropped back on its spot stays; dropped among the hand cards, it joins the hand.
    @MainActor func testCastableCardDraggedIntoHandMovesThere() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-flashback"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        expandPhoneHand(app)
        let castable = app.descendants(matching: .any).matching(identifier: "phone-castable-0").firstMatch
        XCTAssertTrue(castable.waitForExistence(timeout: 5))
        let handCards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-' AND NOT (identifier CONTAINS 'drag')"))
        let handCount = handCards.count
        // A little wiggle that ends where it started changes nothing.
        castable.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            .press(forDuration: 0.3, thenDragTo: castable.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)), withVelocity: 200, thenHoldForDuration: 0.2)
        sleep(1)
        XCTAssertTrue(castable.exists)
        XCTAssertEqual(handCards.count, handCount)
        // Among the hand cards: into the hand.
        let target = app.descendants(matching: .any).matching(identifier: "phone-hand-1").firstMatch
        castable.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            .press(forDuration: 0.3, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 300, thenHoldForDuration: 0.3)
        expectation(for: NSPredicate(format: "count == \(handCount + 1)"), evaluatedWith: handCards)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(castable.exists)
        XCTAssertEqual(app.buttons["phone-graveyard-a"].value as? String, "0")
    }

    /// Search shows the whole library as a scrolling fan (with Shuffle & Done).
    @MainActor func testSearchBrowserShowsWholeLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        let library = app.buttons["phone-library-a"]
        let libraryCount = Int(library.value as? String ?? "0") ?? 0
        openPileMenuItem(app, pile: library, "Search")
        let browser = app.descendants(matching: .any).matching(identifier: "phone-zone-browser").firstMatch
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        XCTAssertEqual(browserCards(app).count, libraryCount)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Search browser"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["phone-browser-secondary"].tap() // Shuffle & Done
        XCTAssertFalse(browser.waitForExistence(timeout: 2))
    }

    /// "Look at" opens the browser on the top cards (the library sheet closes). Cards drop onto the
    /// uncovered library pile (Top / Bottom choice) and graveyard; they can be shown to the opponent.
    @MainActor func testLookAtBrowserMovesCardsToLibraryBottomAndGraveyard() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        let library = app.buttons["phone-library-a"]
        let graveyard = app.buttons["phone-graveyard-a"]
        let libraryCount = Int(library.value as? String ?? "0") ?? 0
        openPileMenuItem(app, pile: library, "Look at")
        app.buttons["2 cards"].tap()
        let browser = app.descendants(matching: .any).matching(identifier: "phone-zone-browser").firstMatch
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        let cards = browserCards(app)
        // The two looked at, then the rest of the library face down.
        XCTAssertEqual(cards.count, libraryCount)
        XCTAssertEqual(cards.matching(NSPredicate(format: "label == 'Face-down card'")).count, libraryCount - 2)
        let show = app.buttons["phone-browser-show-opponent"]
        show.tap()
        XCTAssertEqual(show.value as? String, "On")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Look at browser"; shot.lifetime = .keepAlways; add(shot)
        // Onto the library pile in the uncovered bottom bar: choose Bottom.
        let faceUp = cards.matching(NSPredicate(format: "label != 'Face-down card'"))
        XCTAssertEqual(faceUp.count, 2)
        // The top of the library is on the right, as on Arena.
        XCTAssertGreaterThan(faceUp.element(boundBy: 0).frame.minX, cards.matching(NSPredicate(format: "label == 'Face-down card'")).element(boundBy: 0).frame.minX)
        faceUp.element(boundBy: 0).press(forDuration: 0.4, thenDragTo: library, withVelocity: 300, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.buttons["Bottom"].waitForExistence(timeout: 5))
        app.buttons["Bottom"].tap()
        // Scried to the bottom: it's still in the library, now last in the fan (face up).
        sleep(1)
        XCTAssertEqual(library.value as? String, "\(libraryCount)")
        faceUp.element(boundBy: 0).press(forDuration: 0.4, thenDragTo: graveyard, withVelocity: 300, thenHoldForDuration: 0.3)
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: graveyard)
        waitForExpectations(timeout: 5)
        app.buttons["phone-browser-done"].tap()
        XCTAssertFalse(browser.waitForExistence(timeout: 2))
    }

    /// A Room lies sideways with its locked door marked; its menu locks and unlocks doors.
    @MainActor func testRoomShowsLockedDoorAndUnlocks() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-room"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        app.buttons["phone-stack"].tap()
        let room = app.buttons.matching(NSPredicate(format: "label == 'Test Room'")).firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value CONTAINS 'Back Door locked'"), evaluatedWith: room)
        waitForExpectations(timeout: 10)
        XCTAssertFalse((room.value as? String ?? "").contains("Front Door locked"))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Room with a locked door"; shot.lifetime = .keepAlways; add(shot)
        room.press(forDuration: 0.8)
        let toggle = app.buttons["card-door-lock-1"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        app.buttons["Done"].firstMatch.tap()
        expectation(for: NSPredicate(format: "NOT (value CONTAINS 'locked')"), evaluatedWith: room)
        waitForExpectations(timeout: 5)
    }

    /// Holding a hand card up to read it and letting go without moving reorders nothing.
    @MainActor func testHoldingHandCardWithoutMovingKeepsOrder() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        expandPhoneHand(app)
        func names() -> [String] { (0..<7).map { app.descendants(matching: .any).matching(identifier: "phone-hand-\($0)").firstMatch.label } }
        let before = names()
        app.descendants(matching: .any).matching(identifier: "phone-hand-2").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3)).press(forDuration: 1.0)
        sleep(1)
        XCTAssertEqual(names(), before)
    }

    /// Planets and Spacecraft draw full-art inside their border; a two-card hand fans like the browser.
    @MainActor func testPlanetSpacecraftAndSmallHandScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-planet"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        app.buttons["phone-stack"].tap()
        sleep(1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Planet and Spacecraft"; shot.lifetime = .keepAlways; add(shot)
        expandPhoneHand(app)
        sleep(1)
        let hand = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        hand.name = "Expanded hand fan"; hand.lifetime = .keepAlways; add(hand)
    }

    @MainActor func testLandHoldAndBoardMenuSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        let lands = app.descendants(matching: .any).matching(identifier: "phone-local-lands").firstMatch
        let island = lands.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Island, 5'")).firstMatch
        island.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Switch Control"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Attach to…"].exists)
        XCTAssertFalse(app.buttons["Add Ability to Stack…"].exists)
    }

    @MainActor func testMenuDeckChoosersAndOfflineCatalog() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        app.buttons["phone-settings"].tap()
        XCTAssertTrue(app.navigationBars["Battlefield"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reset Decks and Life"].exists, "Reset options sit on the menu's first page")
        let menuShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); menuShot.name = "Board menu"; menuShot.lifetime = .keepAlways; add(menuShot)
        app.buttons["Load Deck / JumpStart / Jump In"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Load Deck"].waitForExistence(timeout: 5))
        app.buttons["JumpStart (2020)"].tap()
        XCTAssertTrue(app.buttons["phone-packet-choice"].firstMatch.waitForExistence(timeout: 5))
        let choice = NSPredicate(format: "identifier == 'phone-packet-choice'")
        app.buttons.matching(choice).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Choose Second Packet"].waitForExistence(timeout: 5))
        app.buttons.matching(choice).firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Choose Second Packet"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.navigationBars["Deck Ready"].exists)
        XCTAssertFalse(app.buttons["Return to Battlefield"].exists)
        XCTAssertEqual(app.buttons["phone-library-a"].value as? String, "40")
        app.buttons["phone-stack-resolve"].tap()
        XCTAssertFalse(app.buttons["phone-stack"].exists)
    }

    @MainActor func testCreateTokenCopyFromPhoneCardMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let bears = app.buttons.matching(identifier: "phone-creature-card")
            .matching(NSPredicate(format: "label == 'Grizzly Bears'"))
        XCTAssertTrue(bears.firstMatch.waitForExistence(timeout: 15))
        let before = bears.count
        let local = bears.allElementsBoundByIndex.max { $0.frame.midY < $1.frame.midY }!
        local.press(forDuration: 0.7)
        let create = app.buttons["Token Copy"]
        // A tile at the top of the card menu: no scrolling.
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isHittable)
        create.tap()
        expectation(for: NSPredicate { _,_ in bears.count == before + 1 }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        sleep(1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Token copy beside its original"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testQuickDragRemovesCreaturesAndOrganizedLands() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let grave = app.buttons["phone-graveyard-a"]
        XCTAssertTrue(grave.waitForExistence(timeout: 15))
        let bears = app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Grizzly Bears'")).allElementsBoundByIndex
        let own = bears.max { $0.frame.minY < $1.frame.minY }!
        own.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: grave.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertTrue(NSPredicate(format: "value == '1'").evaluate(with: grave))
        let lands = app.descendants(matching: .any).matching(identifier: "phone-local-lands").firstMatch
        let island = lands.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Island, 5'")).firstMatch
        island.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: grave.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertTrue(NSPredicate(format: "value == '2'").evaluate(with: grave))
    }

    @MainActor func testOfflineJumpInAndArtworkBrowser() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        func menu() {
            app.buttons["phone-settings"].tap()
            XCTAssertTrue(app.navigationBars["Battlefield"].waitForExistence(timeout: 5))
        }
        menu()
        app.buttons["Load Deck / JumpStart / Jump In"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Load Deck"].waitForExistence(timeout: 5))
        if !app.buttons["Jump In!"].isHittable { app.swipeUp() }
        app.staticTexts["Jump In!"].tap()
        XCTAssertTrue(app.navigationBars["Jump-In"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["BLB"].waitForExistence(timeout: 5))
        app.buttons["BLB"].tap()
        XCTAssertTrue(app.navigationBars["Choose First Packet"].waitForExistence(timeout: 5))
        do { let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Packet chooser"; shot.lifetime = .keepAlways; add(shot) }
        let packetChoice = NSPredicate(format: "identifier == 'phone-packet-choice'")
        app.buttons.matching(packetChoice).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Choose Second Packet"].waitForExistence(timeout: 5))
        app.buttons.matching(packetChoice).firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Choose Second Packet"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.navigationBars["Deck Ready"].exists)
        XCTAssertFalse(app.buttons["Return to Battlefield"].exists)
        XCTAssertEqual(app.buttons["phone-library-a"].value as? String, "40")
        menu()
        app.buttons["Preloaded Games & Artwork"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Preloaded Games"].waitForExistence(timeout: 5))
        app.buttons["DanDân"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'of 2 images downloaded for offline play'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Accumulated Knowledge'")).firstMatch.tap()
        XCTAssertGreaterThanOrEqual(app.scrollViews.images.count, 2)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Bundled full card and artwork"
        shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testMarvelJumpStartLoadsOffline() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        app.buttons["phone-settings"].tap()
        app.buttons["Load Deck / JumpStart / Jump In"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Load Deck"].waitForExistence(timeout: 5))
        if !app.buttons["Marvel Super Heroes JumpStart"].isHittable { app.swipeUp() }
        app.buttons["Marvel Super Heroes JumpStart"].tap()
        XCTAssertTrue(app.navigationBars["Choose First Packet"].waitForExistence(timeout: 5))
        do { let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Packet chooser"; shot.lifetime = .keepAlways; add(shot) }
        let choice = NSPredicate(format: "identifier == 'phone-packet-choice'")
        XCTAssertTrue(app.buttons.matching(choice).firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(choice).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Choose Second Packet"].waitForExistence(timeout: 5))
        app.buttons.matching(choice).firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Choose Second Packet"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.navigationBars["Deck Ready"].exists)
        XCTAssertFalse(app.buttons["Return to Battlefield"].exists)
        XCTAssertEqual(app.buttons["phone-library-a"].value as? String, "40")
    }

    @MainActor func testExpandedHandReordersAndCollapsesAfterPlaying() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        func handCard(_ index: Int) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "phone-hand-\(index)").firstMatch
        }
        let middle = handCard(3)
        XCTAssertTrue(middle.waitForExistence(timeout: 15))
        middle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        let hand = app.descendants(matching: .any).matching(identifier: "phone-local-hand").firstMatch
        let expanded = NSPredicate(format: "value == 'Expanded'")
        expectation(for: expanded, evaluatedWith: hand)
        waitForExpectations(timeout: 5)
        let name = handCard(1).label
        // Middle-left of each card's uncovered strip: inside the rotated card, not under its neighbour.
        let names = (0..<7).map { handCard($0).label }
        // The hand stays open while the card is dragged within it, so this reorders in the open hand.
        handCard(1).coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45))
            .press(forDuration: 0.7, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.9)),
                   withVelocity: 300, thenHoldForDuration: 0.4)
        XCTAssertNotEqual(handCard(1).label, name)
        XCTAssertTrue(handCard(6).exists, "Reordering lost a card from the hand")
        XCTAssertEqual(Set((0..<7).map { handCard($0).label }), Set(names))
        // Reordering within the hand leaves it open; tapping the battlefield collapses it.
        XCTAssertEqual(hand.value as? String, "Expanded")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        expectation(for: NSPredicate(format: "value == 'Compact'"), evaluatedWith: hand)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "phone-hand-drag-preview").firstMatch.waitForExistence(timeout: 1.5),
                       "The picked-up card didn't land back in the hand")
        // The collapsed hand can't be dragged from; it only expands.
        let count = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'")).count
        handCard(3).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2))
            .press(forDuration: 0.3, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        sleep(1)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'phone-hand-'")).count, count,
                       "A card was dragged out of the collapsed hand")
        if hand.value as? String != "Expanded" { handCard(3).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap() }
        expectation(for: expanded, evaluatedWith: hand)
        waitForExpectations(timeout: 5)
        handCard(3).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2))
            .press(forDuration: 0.7, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        expectation(for: NSPredicate(format: "value == 'Compact'"), evaluatedWith: hand)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "phone-hand-drag-preview").firstMatch.waitForExistence(timeout: 2),
                       "The played card never finished flying to the battlefield")
    }

    @MainActor func testPhoneHandUsesPlaySheetAndPlaysTappedLand() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let land = app.descendants(matching: .any).matching(identifier: "phone-hand-2").firstMatch
        XCTAssertTrue(land.waitForExistence(timeout: 15))
        let compact = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        compact.name = "Compact hand costs"
        compact.lifetime = .keepAlways
        add(compact)
        land.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.15)).tap()
        let expanded = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expanded.name = "Expanded hand costs"
        expanded.lifetime = .keepAlways
        add(expanded)
        land.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.15)).tap()
        let actions = app.tables["phone-hand-actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        let preview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        preview.name = "Rounded card-menu preview"
        preview.lifetime = .keepAlways
        add(preview)
        XCTAssertFalse(app.buttons["Token Copy"].exists)
        XCTAssertFalse(app.buttons["Attach to…"].exists)
        actions.cells.containing(.staticText, identifier: "Play Tapped").firstMatch.tap()
        XCTAssertFalse(actions.waitForExistence(timeout: 1))
        let lands = app.descendants(matching: .any).matching(identifier: "phone-local-lands").firstMatch
        XCTAssertTrue(lands.descendants(matching: .any).matching(NSPredicate(format: "label == 'Island, 1, tapped'")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testPhoneHandSurvivesForegroundAndAcceptsEmptyHandDrops() {
        for empty in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--phone-board-fixture"] + (empty ? ["--phone-board-empty-hand"] : [])
            app.launch()
            XCUIDevice.shared.orientation = .landscapeLeft
            let library = app.buttons["phone-library-a"]
            XCTAssertTrue(library.waitForExistence(timeout: 15))
            let first = app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch
            if !empty { XCTAssertTrue(first.isHittable) }
            let before = empty ? .zero : first.frame
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(library.waitForExistence(timeout: 10))
            if !empty {
                XCTAssertTrue(first.isHittable, "Hand disappeared after foregrounding")
                // Hittable isn't enough: a hand pushed mostly below the screen (only costs showing) is still hittable.
                expectation(for: NSPredicate { _, _ in abs(first.frame.minY - before.minY) < 2 && abs(first.frame.midX - before.midX) < 2 }, evaluatedWith: nil)
                waitForExpectations(timeout: 5)
                XCTAssertEqual(first.frame.minY, before.minY, accuracy: 2, "Hand moved after foregrounding: \(before) -> \(first.frame)")
            }
            let hand = app.descendants(matching: .any).matching(identifier: "phone-local-hand").firstMatch
            library.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.7, thenDragTo: hand.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)),
                       withVelocity: 300, thenHoldForDuration: 0.6)
            expectation(for: NSPredicate(format: "value == '14'"), evaluatedWith: library)
            waitForExpectations(timeout: 5)
            let drawn = app.descendants(matching: .any).matching(identifier: empty ? "phone-hand-0" : "phone-hand-7").firstMatch
            XCTAssertTrue(drawn.waitForExistence(timeout: 5))
            XCTAssertTrue(drawn.isHittable)
            drawn.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.15)).tap()
            expectation(for: NSPredicate(format: "value == 'Expanded'"), evaluatedWith: hand)
            waitForExpectations(timeout: 5)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = empty ? "Empty hand accepts a card after foreground" : "Hand survives foreground"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    @MainActor func testAttachmentPagesSwitchControlsAndCountersStayCircular() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let bearer = app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Grizzly Bears'")).firstMatch
        XCTAssertTrue(bearer.waitForExistence(timeout: 15))
        bearer.press(forDuration: 0.7)
        let pages = app.descendants(matching: .any).matching(identifier: "phone-inspector-pages").firstMatch
        let controls = app.descendants(matching: .any).matching(identifier: "phone-inspector-controls").firstMatch
        XCTAssertTrue(pages.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Attached Cards…"].exists)
        XCTAssertFalse(app.buttons["Unattach"].exists)
        pages.swipeLeft()
        XCTAssertTrue(app.buttons["Unattach"].waitForExistence(timeout: 5))
        controls.swipeLeft()
        controls.swipeLeft()
        let addCounter = app.buttons["counter-add-0"]
        XCTAssertTrue(addCounter.waitForExistence(timeout: 5))
        for index in [0, 1, 3, 4, 5, 6, 7, 8] {
            let frame = app.buttons["counter-add-\(index)"].frame
            XCTAssertEqual(frame.width, frame.height, accuracy: 1)
            XCTAssertGreaterThanOrEqual(frame.width, 32)
            XCTAssertTrue(controls.frame.contains(frame))
        }
        addCounter.tap()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Attachment counter controls with circular palette"
        shot.lifetime = .keepAlways
        add(shot)
        pages.swipeRight()
        XCTAssertFalse(app.buttons["Unattach"].exists)
        pages.swipeLeft()
        XCTAssertTrue(addCounter.waitForExistence(timeout: 5))
        controls.swipeRight()
        controls.swipeRight()
        XCTAssertTrue(app.buttons["Unattach"].waitForExistence(timeout: 5))
    }

    @MainActor func testTappingPreservesCardScaleAndAttackersUseArrows() {
        let app = XCUIApplication()
        // The opponent attacks: tapping your own creature still just taps it (only your own combat
        // turns taps into attack toggles).
        app.launchArguments = ["--phone-board-fixture", "--phone-board-opponent-attacking"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let bears = app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Grizzly Bears'"))
        XCTAssertTrue(bears.firstMatch.waitForExistence(timeout: 15))
        let ordered = bears.allElementsBoundByIndex.sorted { $0.frame.midY < $1.frame.midY }
        let opponent = ordered[0], local = ordered[1]
        let otherFrame = opponent.frame
        let side = local.frame.width
        let arrow = app.descendants(matching: .any).matching(identifier: "phone-attack-indicator").firstMatch
        XCTAssertTrue(arrow.exists)
        local.tap()
        XCTAssertEqual(opponent.frame, otherFrame)
        let rotationBounds = cos(Double.pi / 15) + sin(Double.pi / 15)
        XCTAssertEqual(local.frame.width / rotationBounds, side, accuracy: 2)
        local.tap()
        XCTAssertEqual(opponent.frame, otherFrame)
        XCTAssertEqual(local.frame.width, side, accuracy: 1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Arena-style orange and white attacker arrow"
        shot.lifetime = .keepAlways
        add(shot)
        local.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Switch Control"].waitForExistence(timeout: 5))
        for title in ["Attack and Tap", "Attack without Tapping", "Stop Attacking", "Block…", "End Combat", "Attach to…"] {
            XCTAssertFalse(app.buttons[title].exists)
        }
        // The opponent is attacking, so you can't declare attackers of your own.
        XCTAssertFalse(app.buttons["Attack"].exists)
    }

    /// Attack from the card menu, toggle attackers by tapping, End Combat on the untap button.
    @MainActor func testCombatModeAttackTogglesAndEndCombat() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let untap = app.buttons["phone-untap-local"]
        XCTAssertTrue(untap.waitForExistence(timeout: 15))
        XCTAssertEqual(untap.label, "Untap + Draw")
        func own(_ name: String) -> XCUIElement {
            app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == %@", name))
                .allElementsBoundByIndex.max { $0.frame.midY < $1.frame.midY }!
        }
        own("Grizzly Bears").press(forDuration: 0.7)
        let attack = app.buttons["Attack"]
        XCTAssertTrue(attack.waitForExistence(timeout: 5))
        attack.tap()
        // The inspector closes; the bear attacks (tapped: no vigilance) and combat begins.
        expectation(for: NSPredicate(format: "label == 'End Combat'"), evaluatedWith: untap)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(own("Grizzly Bears").value as? String, "Attacking")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Combat: attacker glow and End Combat"; shot.lifetime = .keepAlways; add(shot)
        // In combat, tapping another creature makes it attack; tapping again takes it out.
        let attackingSoldiers = app.buttons.matching(identifier: "phone-creature-card")
            .matching(NSPredicate(format: "label == 'Soldier' AND value == 'Attacking'"))
        own("Soldier").tap()
        expectation(for: NSPredicate(format: "count == 1"), evaluatedWith: attackingSoldiers)
        waitForExpectations(timeout: 5)
        let rendered = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); rendered.name = "Combat: glow on a rendered mini card"; rendered.lifetime = .keepAlways; add(rendered)
        attackingSoldiers.firstMatch.tap()
        expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: attackingSoldiers)
        waitForExpectations(timeout: 5)
        untap.tap()
        expectation(for: NSPredicate(format: "label == 'Untap'"), evaluatedWith: untap)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(own("Grizzly Bears").value as? String, "Tapped")
    }

    /// While the opponent attacks, dragging your creature onto their attacker blocks it, and the
    /// blocker moves to sit against the attacker.
    @MainActor func testDraggingOntoAttackerBlocks() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-opponent-attacking"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let bears = app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Grizzly Bears'"))
        XCTAssertTrue(bears.firstMatch.waitForExistence(timeout: 15))
        let ordered = bears.allElementsBoundByIndex.sorted { $0.frame.midY < $1.frame.midY }
        let attacker = ordered[0], blocker = ordered[1]
        XCTAssertEqual(attacker.value as? String, "Attacking")
        let before = blocker.frame
        blocker.press(forDuration: 0.1, thenDragTo: attacker, withVelocity: 500, thenHoldForDuration: 0.8)
        expectation(for: NSPredicate(format: "value == 'Blocking'"), evaluatedWith: blocker)
        waitForExpectations(timeout: 5)
        // It now sits just below the attacker, centered on it.
        XCTAssertEqual(blocker.frame.midX, attacker.frame.midX, accuracy: 4)
        // Right below it: room for the attacker's arrow, no more.
        XCTAssertLessThan(blocker.frame.minY - attacker.frame.maxY, 60)
        XCTAssertGreaterThan(blocker.frame.minY, attacker.frame.maxY)
        XCTAssertEqual(app.buttons["phone-untap-local"].value as? String, "1 blocking assignments")
        _ = before
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Blocker against attacker"; shot.lifetime = .keepAlways; add(shot)
        blocker.press(forDuration: 0.7)
        app.buttons["Stop Blocking"].tap()
        XCTAssertEqual(app.buttons["phone-untap-local"].value as? String, "0 blocking assignments")
    }

    /// Instants dragged from the hand now target instead of attaching (see
    /// testHandSpellDraggedOntoCreatureCastsTargetingIt); a battlefield card still attaches.
    @MainActor func testDraggingOntoCardAttachesAndUnattaches() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-stack"].waitForExistence(timeout: 15))
        app.buttons["phone-stack"].tap() // Collapse the stack, clearing the right side of the board.
        let creatures = app.buttons.matching(identifier: "phone-creature-card")
        let bearer = creatures.matching(NSPredicate(format: "label == 'Grizzly Bears'")).allElementsBoundByIndex.max { $0.frame.midY < $1.frame.midY }!
        let soldier = creatures.matching(NSPredicate(format: "label == 'Soldier'")).allElementsBoundByIndex.max { $0.frame.midY < $1.frame.midY }!
        // Attaching needs a short hover over the target (the blue "Attach" glow) before the drop.
        soldier.press(forDuration: 0.05, thenDragTo: bearer, withVelocity: .default, thenHoldForDuration: 0.8)
        bearer.press(forDuration: 0.7)
        let pages = app.descendants(matching: .any).matching(identifier: "phone-inspector-pages").firstMatch
        XCTAssertTrue(pages.waitForExistence(timeout: 5))
        pages.swipeLeft()
        pages.swipeLeft()
        let unattach = app.buttons["Unattach"]
        XCTAssertTrue(unattach.waitForExistence(timeout: 5))
        unattach.tap()
        // Unattach may close the inspector on its own (the card leaves this page).
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 1), done.isHittable { done.tap() }
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pages)
        waitForExpectations(timeout: 5)
        bearer.press(forDuration: 0.7)
        XCTAssertTrue(pages.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Unattach"].exists)
    }

    @MainActor func testLandTapKeepsPhoneBackgroundAndBattlefieldFixed() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let lands = app.descendants(matching: .any).matching(identifier: "phone-local-lands").firstMatch
        XCTAssertTrue(lands.waitForExistence(timeout: 15))
        let background = app.descendants(matching: .any).matching(identifier: "phone-background-logo").firstMatch
        XCTAssertTrue(background.exists)
        let backgroundFrame = background.frame
        // Compare every creature's frame (sorted): `firstMatch` follows view order, which re-layouts may change.
        let creatures = app.buttons.matching(identifier: "phone-creature-card")
        func creatureFrames() -> [CGRect] {
            creatures.allElementsBoundByIndex.map(\.frame).sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
        }
        let creatureFrame = creatureFrames()
        XCTAssertFalse(creatureFrame.isEmpty)
        let land = lands.descendants(matching: .any).matching(NSPredicate(format: "label == 'Island, 5, untapped'")).firstMatch
        XCTAssertTrue(land.exists)
        land.tap()
        XCTAssertEqual(background.frame, backgroundFrame)
        XCTAssertEqual(creatureFrames(), creatureFrame)
        let tapped = lands.descendants(matching: .any).matching(NSPredicate(format: "label == 'Island, 1, tapped'")).firstMatch
        XCTAssertTrue(tapped.waitForExistence(timeout: 5))
        tapped.tap()
        XCTAssertEqual(background.frame, backgroundFrame)
        XCTAssertEqual(creatureFrames(), creatureFrame)
    }

    @MainActor func testDragLibraryCardIntoPhoneHand() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let library = app.buttons["phone-library-a"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        let hand = app.descendants(matching: .any).matching(identifier: "phone-hand-3").firstMatch
        library.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.7, thenDragTo: hand.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.15)),
                   withVelocity: 300, thenHoldForDuration: 0.6)
        expectation(for: NSPredicate(format: "value == '14'"), evaluatedWith: library)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "phone-hand-7").firstMatch.exists)
    }

    @MainActor func testPhoneHandExpandsAndCollapsesWithoutMovingBattlefield() {
        for asGuest in [false,true] { checkPhoneHand(asGuest: asGuest) }
    }

    @MainActor private func checkPhoneHand(asGuest: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"] + (asGuest ? ["--phone-board-as-guest"] : [])
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let card = app.descendants(matching: .any).matching(identifier: "phone-hand-3").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let compactWidth = card.frame.width
        let compactCenter = card.frame.midX
        let creature = app.buttons.matching(identifier: "phone-creature-card").firstMatch
        let center = creature.frame.midX
        let untap = app.buttons["phone-untap-local"]
        let untapFrame = untap.frame
        let library = app.buttons["phone-library-" + (asGuest ? "b" : "a")]
        let libraryFrame = library.frame
        let life = app.descendants(matching: .any).matching(identifier: "phone-life-local").firstMatch
        XCTAssertTrue(life.exists)
        let lifeFrame = life.frame
        let compact = XCTAttachment(screenshot: XCUIScreen.main.screenshot());compact.name="Compact hand";compact.lifetime = .keepAlways;add(compact)
        card.coordinate(withNormalizedOffset: CGVector(dx:0.5,dy:0.15)).tap()
        // Sample mid-animation too: HUD controls must never move, not just end in place.
        for _ in 0..<3 {
            XCTAssertEqual(untap.frame.minY, untapFrame.minY, accuracy: 1)
            XCTAssertEqual(library.frame.minY, libraryFrame.minY, accuracy: 1)
        }
        let enlarged = NSPredicate { _,_ in card.frame.width > compactWidth * 1.2 }
        expectation(for: enlarged,evaluatedWith: nil)
        waitForExpectations(timeout:5)
        XCTAssertEqual(creature.frame.midX,center,accuracy:2)
        XCTAssertEqual(card.frame.midX,compactCenter,accuracy:1)
        for (element, original) in [(untap, untapFrame), (library, libraryFrame), (life, lifeFrame)] {
            XCTAssertEqual(element.frame.minX, original.minX, accuracy: 1)
            XCTAssertEqual(element.frame.minY, original.minY, accuracy: 1)
            XCTAssertEqual(element.frame.width, original.width, accuracy: 1)
            XCTAssertEqual(element.frame.height, original.height, accuracy: 1)
        }
        let expanded = XCTAttachment(screenshot: XCUIScreen.main.screenshot());expanded.name="Expanded hand";expanded.lifetime = .keepAlways;add(expanded)
        // Tapping a battlefield card while expanded only collapses the hand; the card must not tap.
        let creatureValue = creature.value as? String
        creature.coordinate(withNormalizedOffset: CGVector(dx:0.5,dy:0.5)).tap()
        let collapsed = NSPredicate { _,_ in abs(card.frame.width-compactWidth)<3 }
        expectation(for: collapsed,evaluatedWith:nil)
        waitForExpectations(timeout:5)
        XCTAssertEqual(creature.value as? String, creatureValue)
        XCTAssertFalse(app.buttons["phone-untap-opponent"].exists)
    }

    /// Every card of a big hand stays on screen, compact and expanded (rotated ends included).
    @MainActor func testBigHandFitsOnScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-big-hand"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let first = app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let screen = app.windows.firstMatch.frame
        func check(_ state: String) {
            for index in [0, 14] {
                let card = app.descendants(matching: .any).matching(identifier: "phone-hand-\(index)").firstMatch
                XCTAssertTrue(card.exists, "\(state) card \(index)")
                XCTAssertGreaterThanOrEqual(card.frame.minX, screen.minX - 1, "\(state) card \(index) \(card.frame)")
                XCTAssertLessThanOrEqual(card.frame.maxX, screen.maxX + 1, "\(state) card \(index) \(card.frame)")
            }
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Big hand \(state)"; shot.lifetime = .keepAlways; add(shot)
        }
        check("compact")
        app.descendants(matching: .any).matching(identifier: "phone-hand-7").firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        let expanded = app.descendants(matching: .any).matching(identifier: "phone-local-hand").firstMatch
        expectation(for: NSPredicate(format: "value == 'Expanded'"), evaluatedWith: expanded)
        waitForExpectations(timeout: 5)
        check("expanded")
    }

    /// iPhone 8 / iOS 16 landscape sheets can't be swiped away: Phone Play sheets get an explicit close button.
    @MainActor func testPileSheetHasCloseButton() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let library = app.buttons["phone-library-a"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        openPileMenuItem(app, pile: library, "Open List")
        let close = app.buttons["phone-sheet-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2))
        XCTAssertTrue(library.isHittable)
    }

    /// The board stays landscape; pile sheets may rotate to portrait, and closing returns to landscape.
    @MainActor func testBoardIsLandscapeButPileSheetsRotate() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let library = app.buttons["phone-library-a"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        func isLandscape() -> Bool { let f = app.windows.firstMatch.frame; return f.width > f.height }
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(isLandscape(), "Board rotated to portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        openPileMenuItem(app, pile: library, "Open List")
        let close = app.buttons["phone-sheet-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        expectation(for: NSPredicate { _, _ in !isLandscape() }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Pile sheet portrait"; shot.lifetime = .keepAlways; add(shot)
        close.tap()
        expectation(for: NSPredicate { _, _ in isLandscape() }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(library.isHittable)
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    /// Commanders sit off to the side of the hand with a yellow glow (screenshot check).
    @MainActor func testCommanderShowsBesideHand() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-commander"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let last = app.descendants(matching: .any).matching(identifier: "phone-hand-6").firstMatch
        let commander = app.descendants(matching: .any).matching(identifier: "phone-command-0").firstMatch
        XCTAssertTrue(commander.waitForExistence(timeout: 15))
        XCTAssertEqual(commander.label, "Dandân")
        // The gap: the commander starts clearly right of where the hand's overlap would put it.
        XCTAssertGreaterThan(commander.frame.minX - last.frame.minX, (last.frame.width) * 0.6)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Commander beside hand"; shot.lifetime = .keepAlways; add(shot)
        last.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.15)).tap()
        sleep(1)
        let expanded = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); expanded.name = "Commander beside expanded hand"; expanded.lifetime = .keepAlways; add(expanded)
    }

    /// Keyword counters come from the counter palette's menu and show as tiles on the card (screenshot).
    @MainActor func testKeywordCounterFromPalette() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let bear = app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Grizzly Bears'")).firstMatch
        XCTAssertTrue(bear.waitForExistence(timeout: 15))
        bear.press(forDuration: 0.7)
        let controls = app.descendants(matching: .any).matching(identifier: "phone-inspector-controls").firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        controls.swipeLeft()
        controls.swipeLeft()
        let keyword = app.buttons["counter-add-keyword"]
        XCTAssertTrue(keyword.waitForExistence(timeout: 5))
        keyword.tap()
        let flying = app.buttons["Flying"]
        XCTAssertTrue(flying.waitForExistence(timeout: 5))
        flying.tap()
        XCTAssertTrue(app.staticTexts["Flying"].waitForExistence(timeout: 5))
        keyword.tap()
        app.buttons["Deathtouch"].tap()
        for name in ["Exalted"] { // Shadow sits below the menu's fold on the SE.
            keyword.tap()
            app.buttons[name].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        }
        app.buttons["Stun"].tap()
        app.buttons["counter-add-finality"].tap()
        XCTAssertTrue(app.staticTexts["Stun"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Finality"].waitForExistence(timeout: 5))
        let menuShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); menuShot.name = "Keyword counters listed"; menuShot.lifetime = .keepAlways; add(menuShot)
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Keyword counter tiles"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Colors set in a land's properties override its frame colors (screenshot check).
    @MainActor func testLandColorPropertyOverridesFrame() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let lands = app.descendants(matching: .any).matching(identifier: "phone-local-lands").firstMatch
        XCTAssertTrue(lands.waitForExistence(timeout: 15))
        lands.descendants(matching: .any).matching(NSPredicate(format: "label == 'Island, 5, untapped'")).firstMatch.press(forDuration: 0.8)
        let red = app.buttons["card-color-r"]
        let controls = app.descendants(matching: .any).matching(identifier: "phone-inspector-controls").firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        // The right pane pages sideways; Properties may be further down a page.
        search: for _ in 0..<4 {
            for _ in 0..<4 {
                if red.exists && red.isHittable { break search }
                controls.swipeUp()
            }
            controls.swipeLeft()
        }
        XCTAssertTrue(red.waitForExistence(timeout: 5))
        red.tap()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Land made red (inspector)"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        let board = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); board.name = "Land made red (board)"; board.lifetime = .keepAlways; add(board)
    }

    /// Repro for "dragging a card from the battlefield makes the hand disappear" and
    /// "dragging a hand card shows the card menu instead of letting me drag it out".
    @MainActor func testHandStaysThroughBattlefieldDragAndHandDragPlays() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let handCard = app.descendants(matching: .any).matching(identifier: "phone-hand-3").firstMatch
        XCTAssertTrue(handCard.waitForExistence(timeout: 15))
        let handFrame = handCard.frame
        let bears = app.buttons.matching(identifier: "phone-creature-card").matching(NSPredicate(format: "label == 'Grizzly Bears'")).allElementsBoundByIndex
        let own = bears.max { $0.frame.minY < $1.frame.minY }!
        // Drag a battlefield card to an empty spot and back: the hand must stay put and visible.
        own.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45)), withVelocity: 400, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertTrue(handCard.exists, "Hand disappeared after a battlefield drag")
        XCTAssertEqual(handCard.frame.minY, handFrame.minY, accuracy: 2, "Hand moved after a battlefield drag")
        XCTAssertTrue(handCard.isHittable)
        let afterField = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); afterField.name = "After battlefield drag"; afterField.lifetime = .keepAlways; add(afterField)
        // Drag a card out of the (expanded) hand onto the battlefield: it plays, no card sheet.
        let name = handCard.label
        handCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        let hand = app.descendants(matching: .any).matching(identifier: "phone-local-hand").firstMatch
        expectation(for: NSPredicate(format: "value == 'Expanded'"), evaluatedWith: hand)
        waitForExpectations(timeout: 5)
        handCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.6, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)), withVelocity: 400, thenHoldForDuration: 0.4)
        sleep(1)
        XCTAssertFalse(app.tables["phone-hand-actions"].exists, "Dragging a hand card opened the card sheet")
        _ = name
        // 7 cards before; one played (the overlap may hand the press to a neighbour, so count instead of naming).
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "phone-hand-6").firstMatch.exists, "Dragged hand card didn't leave the hand")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "phone-hand-0").firstMatch.isHittable, "Hand disappeared after a hand drag")
        let afterHand = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); afterHand.name = "After hand drag"; afterHand.lifetime = .keepAlways; add(afterHand)
    }

    /// Holds a picked-up hand card over the hand, then over the battlefield, for external screenshots
    /// (`simctl io screenshot` in a loop) of the in-drag sizing, the gap and the landing (not an assertion test).
    @MainActor func testDumpHandDragFrames() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let hand = app.descendants(matching: .any).matching(identifier: "phone-local-hand").firstMatch
        func card(_ index: Int) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "phone-hand-\(index)").firstMatch }
        XCTAssertTrue(card(3).waitForExistence(timeout: 15))
        sleep(2)
        card(3).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        expectation(for: NSPredicate(format: "value == 'Expanded'"), evaluatedWith: hand)
        waitForExpectations(timeout: 5)
        sleep(1)
        print("DRAGDUMP reorder-start")
        card(5).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
            .press(forDuration: 0.7, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.9)), withVelocity: 150, thenHoldForDuration: 2.5)
        sleep(2)
        card(3).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        sleep(1)
        print("DRAGDUMP play-start")
        card(2).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
            .press(forDuration: 0.7, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.42)), withVelocity: 150, thenHoldForDuration: 2.5)
        sleep(3)
    }

    /// Prints HUD/land-row frames for layout polish on any simulator (not an assertion test).
    @MainActor func testBattlefieldCardsStayClearOfLandsAndOtherRows() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-support"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let supports = app.buttons.matching(identifier: "phone-permanent-card").matching(NSPredicate(format: "label == 'Control Magic'"))
        XCTAssertTrue(supports.firstMatch.waitForExistence(timeout: 15))
        let creatures = app.buttons.matching(identifier: "phone-creature-card")
        // The actual land stacks (cards may sit beside them inside the rows' empty area: column layout).
        var lands: [XCUIElement] {
            ["phone-local-lands", "phone-opponent-lands"].flatMap {
                app.descendants(matching: .any).matching(identifier: $0).firstMatch
                    .descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH 'tapped'")).allElementsBoundByIndex
            }
        }
        func checkFrames() {
            XCTAssertFalse(lands.isEmpty, "Land stacks not found")
            let permanents = supports.allElementsBoundByIndex + creatures.allElementsBoundByIndex
            for card in permanents {
                for land in lands { XCTAssertFalse(card.frame.intersects(land.frame), card.label + " overlaps lands") }
            }
            for support in supports.allElementsBoundByIndex {
                for creature in creatures.allElementsBoundByIndex {
                    XCTAssertFalse(support.frame.intersects(creature.frame), "Support overlaps a creature")
                }
            }
            let cards = creatures.allElementsBoundByIndex
            for i in cards.indices {
                // Repeated identical tokens deliberately form a single fanned group.
                for j in cards.indices where i < j && cards[i].label != cards[j].label {
                    XCTAssertFalse(cards[i].frame.intersects(cards[j].frame), "Separate creature groups overlap")
                }
            }
        }
        checkFrames()
        let localBear = creatures.allElementsBoundByIndex.filter { $0.label == "Grizzly Bears" }.max { $0.frame.midY < $1.frame.midY }
        XCTAssertNotNil(localBear)
        localBear?.tap()
        checkFrames()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Battlefield rows without overlap"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testDumpPhoneHUDLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["phone-library-a"].waitForExistence(timeout: 15))
        print("HUDDUMP window \(app.windows.firstMatch.frame)")
        for id in ["phone-graveyard-a", "phone-library-a", "phone-graveyard-b", "phone-library-b", "phone-untap-local",
                   "phone-life-local", "phone-life-opponent", "phone-local-lands", "phone-opponent-lands", "phone-local-hand", "phone-opponent-hand"] {
            let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            print("HUDDUMP \(id) \(element.exists ? String(describing: element.frame) : "missing")")
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "HUD layout"; shot.lifetime = .keepAlways; add(shot)
    }


    /// The collapsed hand never covers the HUD's piles or untap button, and the right-side controls
    /// respect the safe area, in both landscape orientations (e.g. the folded iPhone Duo's camera side).
    @MainActor func testCollapsedHandClearsHUDInBothLandscapeOrientations() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture"]
        app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            let untap = app.buttons["phone-untap-local"]
            XCTAssertTrue(untap.waitForExistence(timeout: 15))
            XCTAssertTrue(untap.isHittable, "untap button covered in \(orientation.rawValue)")
            XCTAssertTrue(app.windows.firstMatch.frame.contains(untap.frame), "untap off screen in \(orientation.rawValue)")
            let hud = [untap, app.buttons["phone-graveyard-a"], app.buttons["phone-library-a"]]
            for index in 0..<7 {
                let card = app.descendants(matching: .any).matching(identifier: "phone-hand-\(index)").firstMatch
                guard card.exists else { continue }
                // Hand cards are rotated; shrink their bounding boxes to the card bodies.
                let body = card.frame.insetBy(dx: card.frame.width * 0.2, dy: card.frame.height * 0.2)
                for control in hud where control.exists {
                    XCTAssertFalse(body.intersects(control.frame), "hand card \(index) covers \(control.identifier) in \(orientation.rawValue)")
                }
            }
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "HUD \(orientation.rawValue)"; shot.lifetime = .keepAlways; add(shot)
        }
    }

    /// The opponent's HUD (life top left, piles top right) comes back unchanged from the background,
    /// including the size-class change of the snapshot iOS takes there (simulated by the flag).
    @MainActor func testOpponentHUDSurvivesBackgrounding() {
        let app = XCUIApplication()
        app.launchArguments = ["--phone-board-fixture", "--phone-board-background-traits"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let life = app.descendants(matching: .any).matching(identifier: "phone-life-opponent").firstMatch
        let graveyard = app.buttons["phone-graveyard-b"]
        let library = app.buttons["phone-library-b"]
        XCTAssertTrue(life.waitForExistence(timeout: 15))
        sleep(2)
        let before = [life.frame, graveyard.frame, library.frame]
        func check(_ label: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Opponent HUD \(label)"; shot.lifetime = .keepAlways; add(shot)
            let width = app.windows.firstMatch.frame.width
            XCTAssertLessThan(life.frame.width, width * 0.4, "opponent life too wide \(label)")
            XCTAssertLessThan(life.frame.midX, width / 2, "opponent life not on the left \(label)")
            XCTAssertTrue(graveyard.exists && library.exists, "opponent piles missing \(label)")
            XCTAssertGreaterThan(graveyard.frame.midX, width / 2, "opponent graveyard not on the right \(label)")
            XCTAssertEqual(life.frame, before[0], "opponent life moved \(label)")
            XCTAssertEqual(graveyard.frame, before[1], "opponent graveyard moved \(label)")
            XCTAssertEqual(library.frame, before[2], "opponent library moved \(label)")
        }
        check("before")
        for round in 1...2 {
            XCUIDevice.shared.press(.home)
            sleep(3)
            app.activate()
            XCTAssertTrue(life.waitForExistence(timeout: 10))
            sleep(2)
            check("after background \(round)")
        }
    }

}
