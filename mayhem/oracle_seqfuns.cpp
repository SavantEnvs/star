// mayhem/oracle_seqfuns.cpp — authored known-answer behavioral oracle for STAR's core sequence
// primitives (source/SequenceFuns.cpp). STAR ships no runnable upstream unit/functional test suite
// (see mayhem/test.sh NOTE), so this asserts EXACT outputs of the same routines the `seqfuns` fuzz
// target drives. It prints one "ok"/"FAIL" line per check and a final "RESULT passed=P failed=F"
// marker, exiting non-zero if any check fails. Because it verifies concrete return values (not exit
// status), neutering the program to exit(0) yields no RESULT marker and the oracle is detected as
// broken — i.e. it is not reward-hackable.
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

#include "SequenceFuns.h"

static int g_pass = 0, g_fail = 0;

static void check(const char *name, bool ok) {
    if (ok) { ++g_pass; printf("  ok   - %s\n", name); }
    else    { ++g_fail; printf("  FAIL - %s\n", name); }
}

int main() {
    // convertNt01234
    check("convertNt01234 A=0", convertNt01234('A') == 0 && convertNt01234('a') == 0);
    check("convertNt01234 C=1", convertNt01234('C') == 1);
    check("convertNt01234 G=2", convertNt01234('G') == 2);
    check("convertNt01234 T=3", convertNt01234('T') == 3);
    check("convertNt01234 other=4", convertNt01234('N') == 4 && convertNt01234('x') == 4);

    // convertNucleotidesToNumbers
    {
        const char *in = "ACGTN";
        char out[5] = {0};
        convertNucleotidesToNumbers(in, out, 5);
        check("convertNucleotidesToNumbers ACGTN->01234",
              out[0]==0 && out[1]==1 && out[2]==2 && out[3]==3 && out[4]==4);
    }

    // reverse-complement (string)
    {
        std::string s = "AACG";
        revComplementNucleotides(s);
        check("revComplementNucleotides(string) AACG->CGTT", s == "CGTT");
    }

    // reverse-complement (char*)
    {
        char in[5] = "AACG";
        char out[4] = {0};
        revComplementNucleotides(in, out, 4);
        check("revComplementNucleotides(char*) AACG->CGTT",
              out[0]=='C' && out[1]=='G' && out[2]=='T' && out[3]=='T');
    }

    // nuclToNumBAM
    check("nuclToNumBAM =/A/C/G/T/N",
          nuclToNumBAM('=')==0 && nuclToNumBAM('A')==1 && nuclToNumBAM('C')==2 &&
          nuclToNumBAM('G')==4 && nuclToNumBAM('T')==8 && nuclToNumBAM('N')==15 &&
          nuclToNumBAM('Z')==15);

    // 2-bit packing + roundtrip (32)
    {
        uint32 out = 123;
        int32 posN = convertNuclStrToInt32(std::string("AC"), out);
        check("convertNuclStrToInt32 AC=1,posN=-1", out == 1u && posN == -1);
        check("convertNuclInt32toString 1,2=AC", convertNuclInt32toString(1u, 2) == "AC");
        uint32 out2 = 0;
        convertNuclStrToInt32(std::string("GT"), out2);
        check("convertNuclStrToInt32 GT=11", out2 == 11u);
        check("convertNuclInt32toString roundtrip GT", convertNuclInt32toString(out2, 2) == "GT");
        uint32 outN = 0;
        int32 pN = convertNuclStrToInt32(std::string("AN"), outN);
        check("convertNuclStrToInt32 AN posN=1", pN == 1);
        int32 pNN = convertNuclStrToInt32(std::string("NN"), outN);
        check("convertNuclStrToInt32 NN=-2 (two Ns)", pNN == -2);
    }

    // 2-bit packing (64) roundtrip
    {
        uint64 out = 0;
        convertNuclStrToInt64(std::string("ACGT"), out);
        check("convertNuclInt64toString roundtrip ACGT", convertNuclInt64toString(out, 4) == "ACGT");
    }

    // Hamming aligner
    {
        uint32 pos = 99;
        uint32 d = localAlignHammingDist(std::string("ACGTACGT"), std::string("GTA"), pos);
        check("localAlignHammingDist GTA in ACGTACGT dist=0 pos=2", d == 0u && pos == 2u);
        uint32 pos2 = 0;
        uint32 d2 = localAlignHammingDist(std::string("AC"), std::string("ACGT"), pos2);
        check("localAlignHammingDist query>text returns text.size+1", d2 == 3u);
    }

    // localSearch over numeric arrays
    {
        char x[4] = {0,1,2,3};
        char y[2] = {2,3};
        uint ix = localSearch(x, 4, y, 2, 0.3);
        check("localSearch finds GT(23) at ix=2", ix == 2u);
    }

    // qualitySplit
    {
        char r[7] = {0,1,2,4,4,0,1};
        uint c0[17]={0}, c1[17]={0}, c2[17]={0};
        uint *cols[3] = { c0, c1, c2 };
        uint n = qualitySplit(r, 7, 16, 1, cols);
        check("qualitySplit finds 2 good regions", n == 2u);
        check("qualitySplit region0 start=0 len=3", c0[0]==0u && c1[0]==3u);
        check("qualitySplit region1 start=5 len=2", c0[1]==5u && c1[1]==2u);
    }

    printf("RESULT passed=%d failed=%d\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
