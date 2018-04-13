# ----------------------------------- #
# Methods for saving figures to files #
# ----------------------------------- #

# TODO: add width and height and figure out how to convert from measures to the
#       pixels that will be expected in the SVG
function savefig_cairosvg(p::ElectronPlot, fn::AbstractString; dpi::Real=96)
    bas, ext = split(fn, ".")
    if !(ext in ["pdf", "png", "ps"])
        error("Only `pdf`, `png` and `ps` output supported")
    end
    # make sure plot window is active
    display(p)

    # write svg to tempfile
    temp = tempname()
    open(temp, "w") do f
        write(f, svg_data(p, ext))
    end

    # hand off to cairosvg for conversion
    run(`cairosvg $temp -d $dpi -o $fn`)

    # remove temp file
    rm(temp)

    # return plot
    p
end

# an alternative way to save plots -- no shelling out, but output less pretty

"""
`savefig(p::Plot, fn::AbstractString, js::Symbol)`

## Arguments

- `p::Plot`: Plotly Plot
- `fn::AbstractString`: Filename with extension (html, pdf, png)
- `js::Symbol`: One of the following:
    - `:local` - reference the javascript from PlotlyJS installation
    - `:remote` - reference the javascript from plotly CDN
    - `:embed` - embed the javascript in output (add's 1.7MB to size)
"""
function savefig_imagemagick(p::ElectronPlot, fn::AbstractString; js::Symbol=js_default[]
                             #   sz::Tuple{Int,Int}=(8,6),
                             #   dpi::Int=300
                             )

    # Extract file type
    suf = split(fn, ".")[end]

    # if html we don't need a plot window
    if suf == "html"
        open(fn, "w") do f
            show(f, MIME"text/html"(), p, js)
        end
        return p
    end

    # for all the rest we need an active plot window
    display(p)

    # we can export svg directly
    if suf == "svg"
        open(fn, "w") do f
            write(f, svg_data(p))
        end
        return p
    end

    # now for the rest we need ImageMagick
    @eval import ImageMagick

    # construct a magic wand and read the image data from png
    wand = ImageMagick.MagickWand()
    # readimage(wand, _img_data(p, "svg"))
    ImageMagick.readimage(wand, base64decode(png_data(p)))
    ImageMagick.resetiterator(wand)

    # # set units to inches
    # status = ccall((:MagickSetImageUnits, ImageMagick.libwand), Cint,
    #       (Ptr{Void}, Cint), wand.ptr, 1)
    # status == 0 && error(wand)
    #
    # # calculate number of rows/cols
    # width, height = sz[1]*dpi, sz[2]*dpi
    #
    # # set resolution
    # status = ccall((:MagickSetImageResolution, ImageMagick.libwand), Cint,
    # (Ptr{Void}, Cdouble, Cdouble), wand.ptr, Cdouble(dpi), Cdouble(dpi))
    # status == 0 && error(wand)
    #
    # # set number of columns and rows
    # status = ccall((:MagickAdaptiveResizeImage, ImageMagick.libwand), Cint,
    #       (Ptr{Void}, Csize_t, Csize_t), wand.ptr, Csize_t(width), Csize_t(height))
    # status == 0 && error(wand)

    # finally write the image out
    ImageMagick.writeimage(wand, fn)

    p
end

function savefig(p::ElectronPlot, fn::AbstractString; js::Symbol=js_default[])
    suf = split(fn, ".")[end]

    # if html we don't need a plot window
    if suf == "html"
        open(fn, "w") do f
            show(f, MIME"text/html"(), p, js)
        end
        return p
    end

    # same for json
    if suf == "json"
        open(fn, "w") do f
            print(f, json(p))
        end
        return p
    end

    # for all the rest we need raw svg data. to get that we'd have to display
    # the plot
    raw_svg = svg_data(p)

    # we can export svg directly
    if suf == "svg"
        open(fn, "w") do f
            write(f, raw_svg)
        end
        return p
    end

    if suf in ["pdf", "png", "eps"]
        _savefig_cairo(p.plot, raw_svg, fn, suf)
    else
        error("Only html, svg, png, pdf, eps output supported")
    end

    fn
end

function png_data(p::ElectronPlot)
    raw = _img_data(p, "png")
    raw[length("data:image/png;base64,")+1:end]
end

function jpeg_data(p::ElectronPlot)
    raw = _img_data(p, "jpeg")
    raw[length("data:image/jpeg;base64,")+1:end]
end

function webp_data(p::ElectronPlot)
    raw = _img_data(p, "webp")
    raw[length("data:image/webp;base64,")+1:end]
end

# the above methods only work with an electron display. For now, we will
# implement them for all other displays simply by loading the plot into an
# electron display and calling the above methods.
for f in [:savefig_cairosvg, :savefig_imagemagick, :savefig,
          :png_data, :jpeg_data, :webp_data]
    @eval function $(f)(p::SyncPlot, args...; kwargs...)
        $(f)(ElectronPlot(p), args...; kwargs...)
        p
    end
end

const _mimeformats =  Dict("application/eps"         => "eps",
                           "image/eps"               => "eps",
                           "application/pdf"         => "pdf",
                           "image/png"               => "png",
                           "image/jpeg"              => "jpeg",
                           "application/postscript"  => "ps",
                           # "image/svg+xml"           => "svg"
)

for func in [:png_data, :jpeg_data, :wepb_data, :svg_data,
             :_img_data, :savefig, :savefig_cairosvg, :savefig_imagemagick]
    @eval function $(func)(::Plot, args...; kwargs...)
        msg = string("$($func) not available without a frontend. ",
                     "Try calling `$($func)(plot(p))` instead")
        error(msg)
    end
end

function savefig_imageexporter(p::Plot, fn::AbstractString)
    cmd = "/Users/sglyon/src/other/image-exporter/bin/plotly-graph-exporter.js"
    format = split(fn, ".")[end]
    run(`$cmd $(JSON.json(p)) --format $format --output $fn`)
end

savefig_imageexporter(p::SyncPlot, args...; kwargs...) = savefig_imageexporter(p.plot, args...; kwargs...)

using Requests
function savefig_imageserver(p::Plot, host, port, fn::AbstractString; kwargs...)
    format = split(fn, ".")[end]
    body = Dict("figure" => JSON.lower(p), "format" => format)
    kw = Dict(kwargs)
    for k in ["scale", "width", "height", "encoded"]
        if haskey(kw, Symbol(k))
            body[k] = kw[Symbol(k)]
        end
    end
    foo = Requests.post("http://$host:$port/", json=body)
    open(fn, "w") do f
        write(f, foo.data)
    end
end

savefig_imageserver(p::SyncPlot, args...; kwargs...) = savefig_imageserver(p.plot, args...; kwargs...)
