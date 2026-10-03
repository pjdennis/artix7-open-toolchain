// Expected contents of every RAM word: unique per (bank, address) and never all-zero, so a
// skipped, shifted or misplaced configuration frame always shows up as a mismatch.
function [31:0] pattern(input [5:0] bank, input [9:0] addr);
  pattern = {addr, bank, ~addr, ~bank};
endfunction
