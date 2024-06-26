pragma circom 2.0.0;

/////////////////////////////////////////////////////////////////////////////////////
/////////////////////// Templates from the circomlib ////////////////////////////////
////////////////// Copy-pasted here for easy reference //////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////

/*
 * Outputs `a` AND `b`
 */
template AND() {
    signal input a;
    signal input b;
    signal output out;

    out <== a*b;
}

/*
 * Outputs `a` OR `b`
 */
template OR() {
    signal input a;
    signal input b;
    signal output out;

    out <== a + b - a*b;
}

/*
 * `out` = `cond` ? `L` : `R`
 */
template IfThenElse() {
    signal input cond;
    signal input L;
    signal input R;
    signal output out;

    out <== cond * (L - R) + R;
}

/*
 * (`outL`, `outR`) = `sel` ? (`R`, `L`) : (`L`, `R`)
 */
template Switcher() {
    signal input sel;
    signal input L;
    signal input R;
    signal output outL;
    signal output outR;

    signal aux;

    aux <== (R-L)*sel;
    outL <==  aux + L;
    outR <== -aux + R;
}

/*
 * Decomposes `in` into `b` bits, given by `bits`.
 * Least significant bit in `bits[0]`.
 * Enforces that `in` is at most `b` bits long.
 */
template Num2Bits(b) {
    signal input in;
    signal output bits[b];

    for (var i = 0; i < b; i++) {
        bits[i] <-- (in >> i) & 1;
        bits[i] * (1 - bits[i]) === 0;
    }
    var sum_of_bits = 0;
    for (var i = 0; i < b; i++) {
        sum_of_bits += (2 ** i) * bits[i];
    }
    sum_of_bits === in;
}

/*
 * Reconstructs `out` from `b` bits, given by `bits`.
 * Least significant bit in `bits[0]`.
 */
template Bits2Num(b) {
    signal input bits[b];
    signal output out;
    var lc = 0;

    for (var i = 0; i < b; i++) {
        lc += (bits[i] * (1 << i));
    }
    out <== lc;
}

/*
 * Checks if `in` is zero and returns the output in `out`.
 */
template IsZero() {
    signal input in;
    signal output out;

    signal inv;

    inv <-- in!=0 ? 1/in : 0;

    out <== -in*inv +1;
    in*out === 0;
}

/*
 * Checks if `in[0]` == `in[1]` and returns the output in `out`.
 */
template IsEqual() {
    signal input in[2];
    signal output out;

    component isz = IsZero();

    in[1] - in[0] ==> isz.in;

    isz.out ==> out;
}

/*
 * Checks if `in[0]` < `in[1]` and returns the output in `out`.
 * Assumes `n` bit inputs. The behavior is not well-defined if any input is more than `n`-bits long.
 */
template LessThan(n) {
    assert(n <= 252);
    signal input in[2];
    signal output out;

    component n2b = Num2Bits(n+1);

    n2b.in <== in[0] + (1<<n) - in[1];

    out <== 1-n2b.bits[n];
}

/////////////////////////////////////////////////////////////////////////////////////
///////////////////////// Templates for this lab ////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////

/*
 * Outputs `out` = 1 if `in` is at most `b` bits long, and 0 otherwise.
 */
template CheckBitLength(b) {
    assert(b < 254);
    signal input in;
    signal output out;

    // TODO

    // num2bits
    signal output bits[b];

    for (var i = 0; i < b; i++) {
        bits[i] <-- (in >> i) & 1;
        bits[i] * (1 - bits[i]) === 0;
    }
    var sum_of_bits = 0;
    for (var i = 0; i < b; i++) {
        sum_of_bits += (2 ** i) * bits[i];
    }

    // check if the sum of bits is equal to the input
    component is_equal = IsEqual();
    is_equal.in[0] <== sum_of_bits;
    is_equal.in[1] <== in;

    out <== is_equal.out;
}

/*
 * Enforces the well-formedness of an exponent-mantissa pair (e, m), which is defined as follows:
 * if `e` is zero, then `m` must be zero
 * else, `e` must be at most `k` bits long, and `m` must be in the range [2^p, 2^p+1)
 */
template CheckWellFormedness(k, p) {
    signal input e;
    signal input m;

    // check if `e` is zero
    component is_e_zero = IsZero();
    is_e_zero.in <== e;

    // Case I: `e` is zero
    //// `m` must be zero
    component is_m_zero = IsZero();
    is_m_zero.in <== m;

    // Case II: `e` is nonzero
    //// `e` is `k` bits
    component check_e_bits = CheckBitLength(k);
    check_e_bits.in <== e;
    //// `m` is `p`+1 bits with the MSB equal to 1
    //// equivalent to check `m` - 2^`p` is in `p` bits
    component check_m_bits = CheckBitLength(p);
    check_m_bits.in <== m - (1 << p);

    // choose the right checks based on `is_e_zero`
    component if_else = IfThenElse();
    if_else.cond <== is_e_zero.out;
    if_else.L <== is_m_zero.out;
    //// check_m_bits.out * check_e_bits.out is equivalent to check_m_bits.out AND check_e_bits.out
    if_else.R <== check_m_bits.out * check_e_bits.out;

    // assert that those checks passed
    if_else.out === 1;
}

/*
 * Right-shifts `b`-bit long `x` by `shift` bits to output `y`, where `shift` is a public circuit parameter.
 */
template RightShift(b, shift) {
    assert(shift < b);
    signal input x;
    signal output y;

    // TODO

    // num2bits
    component n2b = Num2Bits(b);
    n2b.in <== x;

    // right shift
    // bits2num
    component b2n = Bits2Num(b - shift);
    for (var i = 0; i < b - shift; i++) {
        b2n.bits[i] <== n2b.bits[i + shift];
    }
    y <== b2n.out;
}

/*
 * Rounds the input floating-point number and checks to ensure that rounding does not make the mantissa unnormalized.
 * Rounding is necessary to prevent the bitlength of the mantissa from growing with each successive operation.
 * The input is a normalized floating-point number (e, m) with precision `P`, where `e` is a `k`-bit exponent and `m` is a `P`+1-bit mantissa.
 * The output is a normalized floating-point number (e_out, m_out) representing the same value with a lower precision `p`.
 */
template RoundAndCheck(k, p, P) {
    signal input e;
    signal input m;
    signal output e_out;
    signal output m_out;
    assert(P > p);

    // check if no overflow occurs
    component if_no_overflow = LessThan(P+1);
    if_no_overflow.in[0] <== m;
    if_no_overflow.in[1] <== (1 << (P+1)) - (1 << (P-p-1));
    signal no_overflow <== if_no_overflow.out;

    var round_amt = P-p;
    // Case I: no overflow
    // compute (m + 2^{round_amt-1}) >> round_amt
    var m_prime = m + (1 << (round_amt-1));
    //// Although m_prime is P+1 bits long in no overflow case, it can be P+2 bits long
    //// in the overflow case and the constraints should not fail in either case
    component right_shift = RightShift(P+2, round_amt);
    right_shift.x <== m_prime;
    var m_out_1 = right_shift.y;
    var e_out_1 = e;

    // Case II: overflow
    var e_out_2 = e + 1;
    var m_out_2 = (1 << p);

    // select right output based on no_overflow
    component if_else[2];
    for (var i = 0; i < 2; i++) {
        if_else[i] = IfThenElse();
        if_else[i].cond <== no_overflow;
    }
    if_else[0].L <== e_out_1;
    if_else[0].R <== e_out_2;
    if_else[1].L <== m_out_1;
    if_else[1].R <== m_out_2;
    e_out <== if_else[0].out;
    m_out <== if_else[1].out;
}

/*
 * Left-shifts `x` by `shift` bits to output `y`.
 * Enforces 0 <= `shift` < `shift_bound`.
 * If `skip_checks` = 1, then we don't care about the output and the `shift_bound` constraint is not enforced.
 */
template LeftShift(shift_bound) {
    signal input x;
    signal input shift;
    signal input skip_checks;
    signal output y;

    // TODO
    // condition for shift_bound
    var setOne = shift;
    // is Set bit is 1 before
    var isSet = 0;

    // multiply by 2 while cond is true
    component bits2num = Bits2Num(shift_bound);
    component iz[shift_bound];
    
    for (var i = 0 ; i < shift_bound ; i++) {
        iz[i] = IsZero();
        iz[i].in <== setOne;
        setOne -= (1 - iz[i].out);
        bits2num.bits[i] <== iz[i].out * (1-isSet);
        isSet = (0 + iz[i].out);
    }

    y <== bits2num.out * x;

    // shift bound checks
    component is_shift_within_bound = LessThan(shift_bound);
    is_shift_within_bound.in[0] <== shift;
    is_shift_within_bound.in[1] <== shift_bound;

    component or = OR();
    or.a <== is_shift_within_bound.out;
    or.b <== skip_checks;

    or.out === 1;
}

/*
 * Find the Most-Significant Non-Zero Bit (MSNZB) of `in`, where `in` is assumed to be non-zero value of `b` bits.
 * Outputs the MSNZB as a one-hot vector `one_hot` of `b` bits, where `one_hot`[i] = 1 if MSNZB(`in`) = i and 0 otherwise.
 * The MSNZB is output as a one-hot vector to reduce the number of constraints in the subsequent `Normalize` template.
 * Enforces that `in` is non-zero as MSNZB(0) is undefined.
 * If `skip_checks` = 1, then we don't care about the output and the non-zero constraint is not enforced.
 */
template MSNZB(b) {
    signal input in;
    signal input skip_checks;
    signal output one_hot[b];

    // TODO

    // num2bits
    component n2b = Num2Bits(b);
    n2b.in <== in;

    // find the MSNZB
    var isFind = 0;
    for (var i = b-1; i >= 0; i--) {
        one_hot[i] <== n2b.bits[i] * (1 - isFind);
        isFind = isFind + one_hot[i];
    }
    

    // assert that `in` is non-zero
    component is_zero = IsZero();
    is_zero.in <== in;

    component or = OR();
    or.a <== (1 - is_zero.out);
    or.b <== skip_checks;

    or.out === 1;
}

/*
 * Normalizes the input floating-point number.
 * The input is a floating-point number with a `k`-bit exponent `e` and a `P`+1-bit *unnormalized* mantissa `m` with precision `p`, where `m` is assumed to be non-zero.
 * The output is a floating-point number representing the same value with exponent `e_out` and a *normalized* mantissa `m_out` of `P`+1-bits and precision `P`.
 * Enforces that `m` is non-zero as a zero-value can not be normalized.
 * If `skip_checks` = 1, then we don't care about the output and the non-zero constraint is not enforced.
 */
template Normalize(k, p, P) {
    signal input e;
    signal input m;
    signal input skip_checks;
    signal output e_out;
    signal output m_out;
    assert(P > p);

    // TODO
    component msnzb = MSNZB(P+1);
    msnzb.in <== m;
    msnzb.skip_checks <== skip_checks;

    // compute the number of leading zeros
    var lz = 0;
    for (var i = 0; i < P+1; i++) {
        lz += i * msnzb.one_hot[i];
    }

    // compute the new exponent and mantissa
    component left_shift = LeftShift(P+1);
    left_shift.x <== m;
    left_shift.shift <== P - lz;
    left_shift.skip_checks <== skip_checks;

    e_out <== e + lz - p;
    m_out <== left_shift.y;
}

/*
 * Adds two floating-point numbers.
 * The inputs are normalized floating-point numbers with `k`-bit exponents `e` and `p`+1-bit mantissas `m` with scale `p`.
 * Does not assume that the inputs are well-formed and makes appropriate checks for the same.
 * The output is a normalized floating-point number with exponent `e_out` and mantissa `m_out` of `p`+1-bits and scale `p`.
 * Enforces that inputs are well-formed.
 */
template FloatAdd(k, p) {
    signal input e[2];
    signal input m[2];
    signal output e_out;
    signal output m_out;

    // TODO

    // check that the inputs are well-formed
    component cwf1 = CheckWellFormedness(k, p);
    cwf1.e <== e[0];
    cwf1.m <== m[0];
    component cwf2 = CheckWellFormedness(k, p);
    cwf2.e <== e[1];
    cwf2.m <== m[1];
    

    // Calculate magnitudes for comparison
    signal mgn0 <== (e[0] * 2 ** (p + 1)) + m[0];
    signal mgn1 <== (e[1] * 2 ** (p + 1)) + m[1];

    // Compare magnitudes
    component compare = LessThan(k + p + 1);
    compare.in[0] <== mgn1;
    compare.in[1] <== mgn0;

    // Switch components to arrange numbers by magnitude
    signal alpha_e, alpha_m, beta_e, beta_m;
    component switcher_e = Switcher();
    component switcher_m = Switcher();
    switcher_e.sel <== compare.out;
    switcher_m.sel <== compare.out;
    switcher_e.L <== e[0];
    switcher_e.R <== e[1];
    switcher_m.L <== m[0];
    switcher_m.R <== m[1];
    alpha_e <== switcher_e.outR;
    beta_e <== switcher_e.outL;
    alpha_m <== switcher_m.outR;
    beta_m <== switcher_m.outL;

    // Compute the difference in exponents
    signal diff <== alpha_e - beta_e;

    // Check if diff > p + 1 or if alpha_e is zero
    component check1 = LessThan(k);
    check1.in[0] <== p + 1;
    check1.in[1] <== diff;

    component check2 = IsZero();
    check2.in <== alpha_e;

    component both_checks = OR();
    both_checks.a <== check1.out;
    both_checks.b <== check2.out;

    // Perform left shift on the mantissa based on the exponent difference
    component alpha_ls = LeftShift(p + 2);
    alpha_ls.x <== alpha_m;
    alpha_ls.shift <== diff;
    alpha_ls.skip_checks <== 1;

    // Unnormalized mantissa and exponent
    signal unnorm_m <== alpha_ls.y + beta_m;
    signal unnorm_e <== beta_e;

    // Normalize the result
    component normalize = Normalize(k, p, 2 * p + 1);
    normalize.e <== unnorm_e;
    normalize.m <== unnorm_m;
    normalize.skip_checks <== 1;

    // Round the normalized result
    component round = RoundAndCheck(k, p, 2 * p + 1);
    round.e <== normalize.e_out;
    round.m <== normalize.m_out;

    // Select the final output based on the check results
    component if_else_e = IfThenElse();
    if_else_e.cond <== both_checks.out;
    if_else_e.L <== alpha_e;
    if_else_e.R <== round.e_out;

    component if_else_m = IfThenElse();
    if_else_m.cond <== both_checks.out;
    if_else_m.L <== alpha_m;
    if_else_m.R <== round.m_out;

    // Assign the final outputs
    e_out <== if_else_e.out;
    m_out <== if_else_m.out;
}