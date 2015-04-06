module Filters
using Polynomials, Compat, ..Util

include("coefficients.jl")
export FilterCoefficients, ZeroPoleGain, PolynomialRatio, Biquad, SecondOrderSections, coefa, coefb

include("filt.jl")
export DF2TFilter, filtfilt, fftfilt, firfilt

include("design.jl")
export FilterType, Butterworth, Chebyshev1, Chebyshev2, Elliptic,
       Lowpass, Highpass, Bandpass, Bandstop, analogfilter,
       digitalfilter

include("response.jl")
export freqs, freqz, phasez, impz, stepz
end
