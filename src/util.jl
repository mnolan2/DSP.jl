module Util

export unwrap!, unwrap, hilbert, Frequencies, fftintype, fftouttype,
       fftabs2type, fftfreq, rfftfreq, nextfastfft, istft

function unwrap!{T <: FloatingPoint}(m::Array{T}, dim::Integer=ndims(m);
                                     range::Number=2pi)
    thresh = range / 2
    if size(m, dim) < 2
        return m
    end
    for i = 2:size(m, dim)
        d = slicedim(m, dim, i) - slicedim(m, dim, i-1)
        slice_tuple = ntuple(ndims(m), n->(n==dim ? (i:i) : (1:size(m,n))))
        offset = floor((d.+thresh) / (range)) * range
#        println("offset: ", offset)
#        println("typeof(offset): ", typeof(offset))
#        println("typeof(m[slice_tuple...]): ", typeof(m[slice_tuple...]))
#        println("slice_tuple: ", slice_tuple)
#        println("m[slice_tuple...]: ", m[slice_tuple...])
        m[slice_tuple...] = m[slice_tuple...] - offset
    end
    return m
end

function unwrap{T <: FloatingPoint}(m::Array{T}, args...; kwargs...)
    unwrap!(copy(m), args...; kwargs...)
end

function hilbert{T<:FFTW.fftwReal}(x::StridedVector{T})
# Return the Hilbert transform of x (a real signal).
# Code inspired by Scipy's implementation, which is under BSD license.
    N = length(x)
    X = zeros(Complex{T}, N)
    p = FFTW.Plan(x, X, 1, FFTW.ESTIMATE, FFTW.NO_TIMELIMIT)
    FFTW.execute(T, p.plan)
    for i = 2:div(N, 2)+isodd(N)
        @inbounds X[i] *= 2.0
    end
    return ifft!(X)
end
hilbert{T<:Real}(x::AbstractVector{T}) = hilbert(convert(Vector{fftintype(T)}, x))

function hilbert{T<:Real}(x::AbstractArray{T})
    N = size(x, 1)
    xc = Array(fftintype(T), N)
    X = Array(fftouttype(T), N)
    out = similar(x, fftouttype(T))

    p1 = FFTW.Plan(xc, X, 1, FFTW.ESTIMATE, FFTW.NO_TIMELIMIT)
    p2 = FFTW.Plan(X, X, 1, FFTW.BACKWARD, FFTW.ESTIMATE, FFTW.NO_TIMELIMIT)

    normalization = 1/N
    off = 1
    for i = 1:Base.trailingsize(x, 2)
        copy!(xc, 1, x, off, N)

        # fft
        fill!(X, 0)
        FFTW.execute(T, p1.plan)

        # scale real part
        for i = 2:div(N, 2)+isodd(N)
            @inbounds X[i] *= 2.0
        end

        # ifft
        FFTW.execute(T, p2.plan)

        # scale and copy to output
        for j = 1:N
            @inbounds out[off+j-1] = X[j]*normalization
        end

        off += N
    end

    out
end

# Evaluate a window function at n points, returning both the window
# (or nothing if no window) and the squared L2 norm of the window
compute_window(::Nothing, n::Int) = (nothing, n)
function compute_window(window::Function, n::Int)
    win = window(n)::Vector{Float64}
    norm2 = sumabs2(win)
    (win, norm2)
end
function compute_window(window::AbstractVector, n::Int)
    length(window) == n || error("length of window must match input")
    (window, sumabs2(window))
end

backward_plan{T<:Union(Float32, Float64)}(X::AbstractArray{Complex{T}}, Y::AbstractArray{T}) =
    FFTW.Plan(X, Y, 1, FFTW.ESTIMATE, FFTW.NO_TIMELIMIT).plan

function istft{T<:Union(Float32, Float64)}(S::AbstractMatrix{Complex{T}}, wlen::Int, overlap::Int; nfft=nextfastfft(wlen), window::Union(Function,AbstractVector,Nothing)=nothing)
    winc = wlen-overlap
    win, norm2 = compute_window(window, wlen)
    if win != nothing 
      win² = win.^2
    end
    nframes = size(S,2)-1
    outlen = nfft + nframes*winc
    out = zeros(T, outlen)
    tmp1 = similar(S[:,1])
    tmp2 = zeros(T, nfft)
    p = backward_plan(tmp1, tmp2)
    wsum = zeros(outlen)
    for k = 1:size(S,2)
        copy!(tmp1, 1, S, 1+(k-1)*size(S,1), length(tmp1))
        FFTW.execute(p, tmp1, tmp2)
        scale!(tmp2, FFTW.normalization(tmp2))
        if win != nothing
            ix = (k-1)*winc
            for n=1:nfft
                @inbounds out[ix+n] += tmp2[n]*win[n]
                @inbounds wsum[ix+n] += win²[n]
            end
        else
            copy!(out, 1+(k-1)*winc, tmp2, 1, nfft)
        end
    end
    if win != nothing
        for i=1:length(wsum)
            @inbounds wsum[i] != 0 && (out[i] /= wsum[i])
        end
    end
    out
end

## FFT TYPES

# Get the input element type of FFT for a given type
fftintype{T<:Base.FFTW.fftwNumber}(::Type{T}) = T
fftintype{T<:Real}(::Type{T}) = Float64
fftintype{T<:Complex}(::Type{T}) = Complex128

# Get the return element type of FFT for a given type
fftouttype{T<:Base.FFTW.fftwComplex}(::Type{T}) = T
fftouttype{T<:Base.FFTW.fftwReal}(::Type{T}) = Complex{T}
fftouttype{T<:Union(Real,Complex)}(::Type{T}) = Complex128

# Get the real part of the return element type of FFT for a given type
fftabs2type{T<:Base.FFTW.fftwReal}(::Type{Complex{T}}) = T
fftabs2type{T<:Base.FFTW.fftwReal}(::Type{T}) = T
fftabs2type{T<:Union(Real,Complex)}(::Type{T}) = Float64

## FREQUENCY VECTOR

immutable Frequencies <: AbstractVector{Float64}
    nreal::Int
    n::Int
    multiplier::Float64
end

unsafe_getindex(x::Frequencies, i::Int) =
    (i-1+ifelse(i <= x.nreal, 0, -x.n))*x.multiplier
function Base.getindex(x::Frequencies, i::Int)
    (i >= 1 && i <= x.n) || throw(BoundsError())
    unsafe_getindex(x, i)
end
Base.start(x::Frequencies) = 1
Base.next(x::Frequencies, i::Int) = (unsafe_getindex(x, i), i+1)
Base.done(x::Frequencies, i::Int) = i > x.n
Base.size(x::Frequencies) = (x.n,)
Base.similar(x::Frequencies, T::Type, args...) = Array(T, args...)
Base.step(x::Frequencies) = x.multiplier

fftfreq(n::Int, fs::Real=1) = Frequencies(((n-1) >> 1)+1, n, fs/n)
rfftfreq(n::Int, fs::Real=1) = Frequencies((n >> 1)+1, (n >> 1)+1, fs/n)
Base.fftshift(x::Frequencies) = (x.nreal-x.n:x.nreal-1)*x.multiplier

# Get next fast FFT size for a given signal length
const FAST_FFT_SIZES = [2, 3, 5, 7]
nextfastfft(n) = nextprod(FAST_FFT_SIZES, n)
nextfastfft(n1, n2...) = tuple(nextfastfft(n1), nextfastfft(n2...)...)
nextfastfft(n::Tuple) = nextfastfft(n...)

end # end module definition
