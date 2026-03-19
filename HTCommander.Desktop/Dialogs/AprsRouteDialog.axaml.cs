using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class AprsRouteDialog : Window
    {
        public bool Confirmed { get; private set; }
        public string RouteName => NameBox.Text?.Trim() ?? "";
        public string RouteValue => RouteBox.Text?.Trim() ?? "";

        public AprsRouteDialog()
        {
            InitializeComponent();
        }

        public AprsRouteDialog(string name, string route) : this()
        {
            NameBox.Text = name;
            RouteBox.Text = route;
            Title = "Edit APRS Route";
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(NameBox.Text) || string.IsNullOrWhiteSpace(RouteBox.Text))
                return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
