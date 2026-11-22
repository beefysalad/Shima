import Testing
@testable import ShimaCore

@Suite @MainActor struct CameraTests {
    @Test func hoverAloneNeverRequestsOrStarts() {
        let client = FakeCameraClient()
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .music, screenAvailable: true)
        #expect(client.requestCount == 0)
        #expect(client.startCount == 0)
    }

    @Test func openingCameraRequestsPermissionAndStartsOnce() {
        let client = FakeCameraClient()
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        #expect(client.requestCount == 1)
        #expect(client.startCount == 1)
        #expect(camera.model.isRunning)
    }

    @Test func collapseStopsAndReexpandRestarts() {
        let client = FakeCameraClient(permission: .authorized)
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        camera.setContext(mode: .collapsed, tab: .camera, screenAvailable: true)
        #expect(client.stopCount == 1)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        #expect(client.startCount == 2)
    }

    @Test func tabSwitchStops() {
        let client = FakeCameraClient(permission: .authorized)
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        camera.setContext(mode: .expanded, tab: .music, screenAvailable: true)
        #expect(client.stopCount == 1)
        #expect(!camera.model.isRunning)
    }

    @Test(arguments: ["screen lock", "screen sleep", "inactive user session"])
    func unavailableScreenStopsAndWakeRestarts(_ reason: String) {
        let client = FakeCameraClient(permission: .authorized)
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: false)
        #expect(client.stopCount == 1, "\(reason) must stop")
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        #expect(client.startCount == 2)
    }

    @Test func deniedPermissionNeverStarts() {
        let client = FakeCameraClient(requestResult: .denied)
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        camera.setContext(mode: .collapsed, tab: .camera, screenAvailable: true)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        #expect(client.requestCount == 1)
        #expect(client.startCount == 0)
        #expect(camera.model.permission == .denied)
    }

    @Test func latePermissionDoesNotStartCollapsedOrLocked() {
        for (mode, screenAvailable) in [(IslandMode.collapsed, true), (.expanded, false)] {
            let client = FakeCameraClient(requestResult: nil)
            let camera = CameraCoordinator(client: client)
            camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
            camera.setContext(mode: mode, tab: .camera, screenAvailable: screenAvailable)
            client.completePermission(.authorized)
            #expect(client.startCount == 0)
        }
    }

    @Test func latePermissionDoesNotStartMusicTab() {
        let client = FakeCameraClient(requestResult: nil)
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        camera.setContext(mode: .expanded, tab: .music, screenAvailable: true)
        client.completePermission(.authorized)
        #expect(client.startCount == 0)
    }

    @Test func shutdownStopsAndCannotRestart() {
        let client = FakeCameraClient(permission: .authorized)
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        camera.shutdown()
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        #expect(client.stopCount == 1)
        #expect(client.startCount == 1)
    }

    @Test func latePermissionCannotRestartAfterQuit() {
        let client = FakeCameraClient(requestResult: nil)
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        camera.shutdown()
        client.completePermission(.authorized)
        #expect(client.startCount == 0)
    }

    @Test func settingsPermissionChangeCanRecover() {
        let client = FakeCameraClient(permission: .denied)
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        client.permission = .authorized
        camera.refreshPermission()
        #expect(client.startCount == 1)
        client.permission = .denied
        camera.refreshPermission()
        #expect(client.stopCount == 1)
    }

    @Test func revokedPermissionCannotBrieflyStartOnReopen() {
        let client = FakeCameraClient(permission: .authorized)
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        camera.setContext(mode: .collapsed, tab: .camera, screenAvailable: true)
        client.permission = .denied
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        #expect(client.startCount == 1)
        #expect(client.stopCount == 1)
        #expect(!camera.model.isRunning)
    }

    @Test func hiddenCameraDoesNotRequestPermission() {
        for (mode, screenAvailable) in [(IslandMode.collapsed, true), (.expanded, false)] {
            let client = FakeCameraClient()
            let camera = CameraCoordinator(client: client)
            camera.setContext(mode: mode, tab: .camera, screenAvailable: screenAvailable)
            #expect(client.requestCount == 0)
            #expect(client.startCount == 0)
        }
    }

    @Test func wakingInMusicTabDoesNotRestartCamera() {
        let client = FakeCameraClient(permission: .authorized)
        let camera = CameraCoordinator(client: client)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: true)
        camera.setContext(mode: .expanded, tab: .camera, screenAvailable: false)
        camera.setContext(mode: .expanded, tab: .music, screenAvailable: false)
        camera.setContext(mode: .expanded, tab: .music, screenAvailable: true)
        #expect(client.startCount == 1)
        #expect(client.stopCount == 1)
        #expect(!camera.model.isRunning)
    }

    @Test func collapseResetsCameraSelectionBeforeHoverReopens() {
        let state = AppState()
        let client = FakeCameraClient(permission: .authorized)
        let camera = CameraCoordinator(client: client)
        state.onCameraContextChange = { mode, tab in
            camera.setContext(mode: mode, tab: tab, screenAvailable: true)
        }
        state.mode = .expanded
        state.selectedTab = .camera
        #expect(client.startCount == 1)
        state.mode = .collapsed
        #expect(state.selectedTab == .music)
        #expect(client.stopCount == 1)
        state.mode = .expanded
        #expect(client.startCount == 1)
        #expect(!camera.model.isRunning)
        state.selectedTab = .camera
        #expect(client.startCount == 2)
    }

    @Test func latePermissionAfterCollapseAndHoverNeedsExplicitCameraClick() {
        for grantBeforeHover in [true, false] {
            let state = AppState()
            let client = FakeCameraClient(requestResult: nil)
            let camera = CameraCoordinator(client: client)
            state.onCameraContextChange = { mode, tab in
                camera.setContext(mode: mode, tab: tab, screenAvailable: true)
            }
            state.mode = .expanded
            state.selectedTab = .camera
            #expect(client.requestCount == 1)
            state.mode = .collapsed
            if grantBeforeHover { client.completePermission(.authorized) }
            state.mode = .expanded
            if !grantBeforeHover { client.completePermission(.authorized) }
            #expect(client.startCount == 0)
            #expect(state.selectedTab == .music)
            state.selectedTab = .camera
            #expect(client.startCount == 1)
            #expect(client.requestCount == 1)
        }
    }

    @Test func appStateDeliversEveryTransitionSynchronously() {
        let state = AppState()
        var transitions: [(IslandMode, IslandTab)] = []
        state.onCameraContextChange = { transitions.append(($0, $1)) }
        state.mode = .expanded
        state.selectedTab = .camera
        state.mode = .collapsed
        #expect(transitions.count == 4)
        #expect(transitions.last?.0 == .collapsed)
        #expect(transitions.last?.1 == .music)
    }
}
