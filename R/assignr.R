
#' @importFrom stringr str_which
detect_positions = function(x, value) {
  stringr::str_which(x, value)
}

find_matching_regions = function(x, value, chunk_lines) {
  # find start of chunks that contain value
  indices_start = detect_positions(x, value)

  # find the chunk end
  indices_end = chunk_lines[which(chunk_lines %in% indices_start) + 1]

  # Kill the process if it is not formatted correctly.
  if(length(indices_end) >= 1 && any(x[indices_end] != "```")) {
    stop("Code chunks not found at the end of code chunk on lines:",
         paste0(which(x[indices_end] != ""), collapse=","))
  }

  # Return as a list
  list("indices_start" = indices_start,
       "indices_end"   = indices_end)
}

# Flatten regions into a numeric vector
condense_regions = function(regions) {
  c(regions$indices_start, regions$indices_end)
}

#' @importFrom purrr map2 flatten_int
chunk_line_ranges = function(regions) {
  # Get line indices from the start to the end (e.g. the range)
  flatten_int(map2(regions$indices_start, regions$indices_end, ~ seq(.x, .y)))
}


removal_indices = function(x, value, chunk_lines) {
  # Obtain the starting and ending indexes for a value
  regions = find_matching_regions(x, value, chunk_lines)

  # Generate the range from start to end
  chunk_line_ranges(regions)
}


#' @importFrom rmarkdown render
#' @importFrom utils zip
generate_hw_pkg = function(x,
                           remove_indexes,
                           name,
                           type,
                           output_dir = paste0(name, "-", type),
                           render_files = TRUE,
                           zip_files = TRUE,
                           file_dependencies = NULL) {

  if (length(remove_indexes) > 0) {
    # create assignment output lines
    x = x[-remove_indexes]
  }

  output_name = paste0(name, "-", type)
  output_path = file.path(output_dir, output_name)

  # Remove the output directory
  if (dir.exists(output_path)) {
    unlink(output_path, recursive = TRUE)
  }

  # Make the directory
  dir.create(output_path, recursive = TRUE)

  # Fill directory
  if(length(file_dependencies) >= 1) {
    file.copy(file_dependencies,
              file.path(output_path, basename(file_dependencies)))
  }

  # Name of Rmd file to build
  rmd_material_name = file.path(output_path,
                                paste0(output_name, ".Rmd"))

  message("Building ", output_name, " files")

  # write to .Rmd, then render as html and pdf
  writeLines(x, rmd_material_name)

  if (render_files) {
    rmarkdown::render(
      rmd_material_name,
      encoding = "UTF-8",
      envir = new.env(),
      output_format = c("html_document", "pdf_document"),
      quiet = TRUE
    )
  }

  if (zip_files) {
    message("Creating a zip file for ", output_name)

    # Zip file together in the output directory
    zip(file.path(output_path, output_name),
        list.files(output_path, full.names = TRUE),
        flags = "-r9XqT") # suppress zip information
  }
}


extract_hw_name = function(x) {
  stringr::str_replace(basename(x),
                       "-.*", "")

}

hw_dir_dependencies = function(x) {
  main_dir_files = list.files(dirname(x), full.names = TRUE, recursive = TRUE)
  grep(main_dir_files, pattern='-(main|assign|sol)', invert=TRUE, value=TRUE)
}

#' Retrieve example file path
#'
#' Obtains the file path for the example Rmd in the package.
#' @param x A `character` containing the name of the example Rmd.
#'
#' @return File path to the example file that ships with the package.
#' @details
#' The following example files ship with the package:
#' - hw00-main.Rmd
#' @export
#' @examples
#' get_example_filepath("hw00-main.Rmd")
get_example_filepath = function(x) {
  fp_example = system.file( "example_rmd" , x , package = "assignr")

  if(!file.exists(fp_example)) {
    stop("Not a valid file path for an example Rmd.")
  }

  fp_example
}


#' Create Homework and Assignment Materials
#'
#' Transforms an RMarkdown file into two separate files: `filename-assign`
#' and `filename-solutions`
#'
#' @param file         Input `.Rmd` file with `-main.Rmd` in the filename.
#' @param output_dir   Output directory. Defaults to name of prefix of filename.
#' @param soln_file    Generate Solution Material. Default is `TRUE`.
#' @param assign_file  Generate Student Assignment Material. Default is `TRUE`.
#' @param zip_files    Create a zip file containing the relevant materials.
#'                     Default is `TRUE`.
#' @param render_files Create HTML and PDF output for each Rmd file.
#'                     Default is `TRUE`.
#' @export
#' @return The function will generate assignment files for students and
#' solution keys for instructors.
#'
#' @details
#' The `file` parameter _must_ have the suffix `-main.Rmd`. The reason for
#' requiring this naming scheme is all work should be done in the "main"
#' document. By enforcing the naming requirement, we are prevent work from
#' being overridden.
#'
#' @section Folder structure:
#' If `output_dir` is specified, then it will be used as the parent
#' for two folders: `*-assign` and `*-sol`, where `*` is given by the part
#' preceeding `-main.Rmd`. Inside the folders, there will be `html`, `pdf`,
#' and `Rmd` documents alongside a `zip` a folder containing all of the
#' documents.
#'
#' @examples
#' hw00_file = get_example_filepath("hw00-main.Rmd")
#'
#' if(interactive()) {
#'     file.show(hw00_file)
#' }
#'
#' assignr(hw00_file, "test")
assignr = function(file,
                   output_dir = NULL,
                   assign_file = TRUE,
                   soln_file = TRUE,
                   zip_files = TRUE,
                   render_files = TRUE) {

  if (length(file) != 1) {
    stop("Only one file may be processed at time.")
  } else if (!grep( "-main.Rmd$", file)) {
    stop("Supplied file must have -main.Rmd")
  }

  hw_name = extract_hw_name(file)

  hw_dependency_files = hw_dir_dependencies(file)

  input_lines = readLines(file)

  chunk_tick_lines = detect_positions(input_lines,  "```")

  solution_indexes  = removal_indices(
    input_lines,
    "solution[[:space:]]?=[[:space:]]?[tT]?[rR]?[uU]?[eE]?",
    chunk_tick_lines
  )

  direction_regions = find_matching_regions(
    input_lines,
    "directions[[:space:]]?=[[:space:]]?[Tt]?[rR]?[uU]?[eE]?",
    chunk_tick_lines
  )

  # Retains direction text
  direction_chunk_indices = condense_regions(direction_regions)

  # Deletes direction text
  direction_regions_range = chunk_line_ranges(direction_regions)


  asis_indexes = condense_regions(find_matching_regions(input_lines,
                                                        "asis",
                                                        chunk_tick_lines))

  if (is.null(output_dir)) {
    output_dir = hw_name
  }

  if (assign_file) {
    generate_hw_pkg(
      x = input_lines,
      remove_indexes = c(solution_indexes, direction_chunk_indices),
      name = hw_name,
      type = "assign",
      output_dir = output_dir,
      render_files = render_files,
      zip_files = zip_files,
      file_dependencies = hw_dependency_files
    )
  }

  if (soln_file) {
    generate_hw_pkg(
      x = input_lines,
      remove_indexes = c(asis_indexes, direction_regions_range),
      name = hw_name,
      type = "soln",
      output_dir = output_dir,
      render_files = render_files,
      zip_files = zip_files,
      file_dependencies = hw_dependency_files
    )
  }

}
