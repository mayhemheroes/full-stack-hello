/* Weak __asan_default_options baked into the sanitized as_exec binary.
 *
 * as_exec is a short-lived, run-once-per-input CLI (assemble a .s source file, then execute it on the
 * register VM). Its assemble + run paths intentionally do NOT free everything before exit — interned
 * operand strings (as.c:quoted_strdup), VM labels (vm.c:vm_make_label), and the vm_env itself on some
 * paths persist until process exit. Under ASan's default leak detection those benign process-exit
 * leaks fire on essentially EVERY input, which would drown out the real memory-safety bugs Mayhem is
 * meant to find in the assembler / interpreter / ELF-reader. Disable leak detection (detect_leaks=0)
 * while keeping all of ASan's heap/stack/global out-of-bounds and use-after-free checks ON and
 * halting. Linked as a weak symbol so it is a default that can still be overridden at runtime via
 * ASAN_OPTIONS if ever needed.
 *
 * NOTE: we do NOT set ASAN_OPTIONS in the Mayhemfile (Mayhem owns the runtime option set); baking the
 * default into the binary is the supported way to turn leak detection off for fuzzing.
 */
const char *__asan_default_options(void) {
    return "detect_leaks=0";
}
