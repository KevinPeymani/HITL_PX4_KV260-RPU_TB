# List the NuttX tasks of the halted R5: source xsdb_tasks.tcl
proc rd {a} { return [lindex [mrd -value $a] 0] }
proc rdstr {a} {
    set s ""
    foreach w [mrd -value $a 7] {
        for {set i 0} {$i < 4} {incr i} {
            set c [expr {($w >> (8 * $i)) & 0xff}]
            if {$c == 0} { return $s }
            append s [format %c $c]
        }
    }
    return $s
}
set states {INVALID PENDING READY RUNNING INACTIVE WAIT_SEM WAIT_SIG/SLEEP MQ_EMPTY MQ_FULL STOPPED}
set n [rd 0x3c17edc8]
set hash [rd 0x3c17edcc]
puts [format "%-4s %-26s %-4s %-14s %-10s %-10s %-10s" pid name prio state waitobj pc lr]
for {set i 0} {$i < $n} {incr i} {
    set tcb [rd [expr {$hash + 4 * $i}]]
    if {$tcb == 0} { continue }
    set st [expr {[rd [expr {$tcb + 68}]] & 0xff}]
    set regs [rd [expr {$tcb + 172}]]
    set lr [expr {$regs ? [rd [expr {$regs + 34 * 4}]] : 0}]
    set pc [expr {$regs ? [rd [expr {$regs + 48 * 4}]] : 0}]
    puts [format "%-4d %-26s %-4d %-14s 0x%08x 0x%08x 0x%08x" \
        [rd [expr {$tcb + 52}]] [rdstr [expr {$tcb + 180}]] \
        [expr {[rd [expr {$tcb + 56}]] & 0xff}] [lindex $states $st] \
        [rd [expr {$tcb + 120}]] $pc $lr]
}

# Dump a task's stack to stack_<pid>.txt: tstack <pid> ?words?
set ::tasks_dir [file dirname [info script]]
proc tstack {pid {words 512}} {
    set n [rd 0x3c17edc8]
    set tcb [rd [expr {[rd 0x3c17edcc] + 4 * ($pid % $n)}]]
    set regs [rd [expr {$tcb + 172}]]
    set sp [rd [expr {$regs + 33 * 4}]]
    set f [open [file join $::tasks_dir stack_$pid.txt] w]
    puts $f [format "sp 0x%08x pc 0x%08x lr 0x%08x" $sp [rd [expr {$regs + 48 * 4}]] [rd [expr {$regs + 34 * 4}]]]
    set a $sp
    foreach w [mrd -value $sp $words] { puts $f [format "0x%08x 0x%08x" $a $w]; incr a 4 }
    close $f
}
