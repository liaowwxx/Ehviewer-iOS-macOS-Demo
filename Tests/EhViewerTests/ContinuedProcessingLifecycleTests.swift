import Testing
import EHDomain

struct ContinuedProcessingLifecycleTests {
    @Test("Work finishing before launch preserves its result", arguments: [true, false])
    func completionBeforeLaunch(success: Bool) {
        var lifecycle = ContinuedProcessingLifecycle()
        #expect(lifecycle.submit() == true)
        #expect(lifecycle.finish(success: success) == false)
        #expect(lifecycle.canSubmit == false)
        #expect(lifecycle.isProcessing == false)
        #expect(lifecycle.submit() == false)
        #expect(lifecycle.launch() == .complete(success: success))
        #expect(lifecycle.canSubmit)
    }

    @Test("Shutdown and later events cannot overwrite a terminal result")
    func firstCompletionWins() {
        var lifecycle = ContinuedProcessingLifecycle()
        lifecycle.submit()
        lifecycle.finish(success: true)
        lifecycle.finish(success: false)
        #expect(lifecycle.launch() == .complete(success: true))
    }

    @Test("Repeated requests and launch callbacks cannot replace a running task")
    func duplicateLaunch() {
        var lifecycle = ContinuedProcessingLifecycle()
        #expect(lifecycle.submit() == true)
        #expect(lifecycle.submit() == false)
        #expect(lifecycle.launch() == .run)
        #expect(lifecycle.launch() == .duplicate)
        #expect(lifecycle.isProcessing)
        #expect(lifecycle.finish(success: true) == true)
        #expect(lifecycle.finish(success: false) == false)
        #expect(lifecycle.canSubmit)
    }

    @Test("A rejected submission permits a retry")
    func retrySubmission() {
        var lifecycle = ContinuedProcessingLifecycle()
        lifecycle.submit()
        lifecycle.submissionFailed()
        #expect(lifecycle.canSubmit)
        #expect(lifecycle.submit() == true)
        #expect(lifecycle.launch() == .run)
    }

    @Test("A new batch starts only after the old completion is delivered")
    func successiveBatches() {
        var lifecycle = ContinuedProcessingLifecycle()
        lifecycle.submit()
        lifecycle.finish(success: false)
        #expect(lifecycle.submit() == false)
        #expect(lifecycle.launch() == .complete(success: false))
        #expect(lifecycle.submit() == true)
        #expect(lifecycle.launch() == .run)
        #expect(lifecycle.finish(success: true) == true)
    }

    @Test("Unexpected callbacks do not leave a task running")
    func unexpectedLaunch() {
        var lifecycle = ContinuedProcessingLifecycle()
        #expect(lifecycle.launch() == .complete(success: false))
        #expect(lifecycle.canSubmit)
    }
}
