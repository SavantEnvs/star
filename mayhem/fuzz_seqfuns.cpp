// mayhem/fuzz_seqfuns.cpp — in-process libFuzzer harness driving STAR's core sequence primitives
// (source/SequenceFuns.cpp): nucleotide<->number conversion, complement / reverse-complement, BAM
// nucleotide packing, 2-bit int packing + roundtrip, the local-search / Hamming aligners, and the
// quality splitter. These are the self-contained algorithmic routines every STAR read passes through;
// the harness feeds one fuzz buffer through all of them with correctly-sized output buffers so any
// crash reflects a genuine defect in the harnessed code, not a harness-introduced overflow.
#include <algorithm>
#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>

#include "SequenceFuns.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    if (Size == 0) return 0;
    if (Size > 4096) Size = 4096;   // bound the O(n^2) aligners so smoke/runs stay responsive

    const char *R0 = reinterpret_cast<const char *>(Data);
    const uint L = static_cast<uint>(Size);

    // 1) ACGT -> 0..4 numeric codes (two variants)
    std::vector<char> nums(L);
    convertNucleotidesToNumbers(R0, nums.data(), L);
    std::vector<char> numsRC(L);
    convertNucleotidesToNumbersRemoveControls(R0, numsRC.data(), L);

    // 3) numeric complement
    std::vector<char> comp(L);
    complementSeqNumbers(nums.data(), comp.data(), L);

    // 4) reverse-complement (char* form reads R0, writes rc)
    std::vector<char> rc(L);
    revComplementNucleotides(const_cast<char *>(R0), rc.data(), L);

    // 5) reverse-complement (std::string, in place)
    std::string s(R0, L);
    revComplementNucleotides(s);

    // 6) BAM 4-bit packing (writes L/2, +1 when odd)
    std::vector<char> packed(L + 1);
    nuclPackBAM(const_cast<char *>(R0), packed.data(), L);

    // 7) per-char converters
    volatile char sink = 0;
    for (uint i = 0; i < L; ++i) {
        sink = (char)(sink ^ nuclToNumBAM(R0[i]));
        sink = (char)(sink ^ convertNt01234(R0[i]));
    }

    // 8) 2-bit string<->int packing + roundtrip on bounded prefixes
    {
        std::string p32(R0, std::min<size_t>(L, 16));
        uint32 out32 = 0;
        convertNuclStrToInt32(p32, out32);
        std::string b32 = convertNuclInt32toString(out32, (uint32)p32.size());
        (void)b32;

        std::string p64(R0, std::min<size_t>(L, 32));
        uint64 out64 = 0;
        convertNuclStrToInt64(p64, out64);
        std::string b64 = convertNuclInt64toString(out64, (uint32)p64.size());
        (void)b64;
    }

    // 9) local search aligners over numeric halves (indices stay in-bounds by construction)
    if (L >= 2) {
        uint nx = L / 2, ny = L - nx;
        const char *x = nums.data();
        const char *y = nums.data() + nx;
        volatile uint r1 = localSearch(x, nx, y, ny, 0.3);
        volatile uint r2 = localSearchNisMM(x, nx, y, ny, 0.3);
        (void)r1; (void)r2;
    }

    // 10) Hamming aligner: query is a bounded prefix of the (reverse-complemented) text
    if (L >= 2) {
        std::string query = s.substr(0, std::min<size_t>(L, 8));
        uint32 pos = 0;
        volatile uint32 hd = localAlignHammingDist(s, query, pos);
        (void)hd;
    }

    // 11) quality splitter over the numeric codes
    {
        const uint maxNsplit = 16;
        std::vector<uint> c0(maxNsplit + 1, 0), c1(maxNsplit + 1, 0), c2(maxNsplit + 1, 0);
        uint *cols[3] = { c0.data(), c1.data(), c2.data() };
        volatile uint ns = qualitySplit(nums.data(), L, maxNsplit, 1, cols);
        (void)ns;
    }

    (void)sink;
    return 0;
}
