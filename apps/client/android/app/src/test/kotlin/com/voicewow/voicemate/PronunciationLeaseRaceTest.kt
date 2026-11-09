package com.voicewow.voicemate

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import org.junit.Assert.*
import org.junit.Test

class PronunciationLeaseRaceTest {
    @Test fun cancelledReplacedAndRetiredOperationsCannotCommit() {
        val lease = PronunciationLease()
        var commits = 0
        val cancelled = lease.claim(1)
        assertTrue(lease.cancel(1))
        assertFalse(lease.withCurrent(1, cancelled) { commits++ })
        val replaced = lease.claim(1)
        val current = lease.claim(2)
        assertFalse(lease.withCurrent(1, replaced) { commits++ })
        assertTrue(lease.withCurrent(2, current) { commits++ })
        lease.retire()
        assertFalse(lease.withCurrent(2, current) { commits++ })
        assertEquals(1, commits)
    }

    @Test fun cancellationWaitsForTheCurrentCommitAndBlocksLaterCommits() {
        val lease = PronunciationLease()
        val ticket = lease.claim(1)
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val cancelling = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)
        try {
            val commit = pool.submit<Boolean> {
                lease.withCurrent(1, ticket) { entered.countDown(); check(release.await(2, TimeUnit.SECONDS)) }
            }
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            val cancel = pool.submit<Boolean> { cancelling.countDown(); lease.cancel(1) }
            assertTrue(cancelling.await(2, TimeUnit.SECONDS))
            assertThrows(TimeoutException::class.java) { cancel.get(50, TimeUnit.MILLISECONDS) }
            release.countDown()
            assertTrue(commit.get(2, TimeUnit.SECONDS))
            assertTrue(cancel.get(2, TimeUnit.SECONDS))
            assertFalse(lease.withCurrent(1, ticket) { fail("Cancelled diagnostic committed") })
        } finally {
            release.countDown()
            pool.shutdownNow()
        }
    }
}
