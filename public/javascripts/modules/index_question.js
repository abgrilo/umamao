$(document).ready(function() {
  $(".question form.vote-up-form input[name=vote_up]").live("click", function(event) {
    var btn_name = $(this).attr("name");
    var form = $(this).parents("form");
    $.post(form.attr("action"), form.serialize()+"&"+btn_name+"=1", function(data){
      if(data.success){
        if(data.vote_type == "vote_down") {
          form.html("<img src='/images/dialog-ok-apply.png'/>");
        } else {
          form.html("<img src='/images/dialog-ok-apply.png'/>");
        }
        showMessage(data.message, "notice");
      } else {
        showMessage(data.message, "error");
      }
    }, "json");
    return false;
  });
});
